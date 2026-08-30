# CMake Build System — PPE42 Test Images

## What is CMake?

CMake is a **meta-build system** — it does not compile code itself. Instead it
reads your `CMakeLists.txt` files and generates the input files for a real build
tool (Ninja, Make, etc.), which then drives the actual compiler and linker.

```
Your CMakeLists.txt files
        │
        ▼
   cmake (configure step)
        │  generates
        ▼
  build/build.ninja   ◄─── Ninja reads this
        │
        ▼
  clang → .o files → ld.lld → hello.elf → hello.dis + hello.bin
```

---

## Key CMake Concepts

### `CMakeLists.txt`
Every directory that participates in the build contains one. They form a tree
that mirrors the source tree. The root file ties everything together via
`add_subdirectory()` calls.

### `project()`
Declares the project name and languages. Must appear once at the top of the root
`CMakeLists.txt`. This project declares both `C` and `ASM` because the kernel
contains assembly source files.

### `add_library()`
Defines a library target — static (`.a`), shared (`.so`), or header-only
(`INTERFACE`).

### `add_executable()`
Defines an executable target (produces an ELF image here).

### `target_include_directories()`
Tells the compiler where to find headers for a target. The visibility keyword
controls propagation:

| Keyword     | Applied to this target | Propagated to consumers |
|-------------|------------------------|-------------------------|
| `PRIVATE`   | ✓                      | ✗                       |
| `PUBLIC`    | ✓                      | ✓                       |
| `INTERFACE` | ✗                      | ✓                       |

### `target_link_libraries()`
Links targets together and automatically propagates `PUBLIC` include paths and
compile definitions to consumers — no need to repeat them.

### `add_compile_options()`
Sets compiler flags project-wide. Every target in the build inherits them
automatically. Individual targets never need to repeat these flags.

### `cmake_parse_arguments()`
Used inside CMake functions to parse named keyword arguments — similar to
keyword arguments in Python. Enables clean, readable function call syntax like:
```cmake
ppe42_firmware(hello
    LINKER_SCRIPT linker/ppe42.ld
    KERNEL        kernel
    LIBS          printf mylib
)
```

### Toolchain File (`cmake/ppe42-clang.cmake`)
Loaded before anything else during configure. Sets `CMAKE_C_COMPILER`,
cross-compilation target flags (`-target powerpc-unknown-elf`, `-mcpu=ppe42`,
`-msoft-float`, `-fuse-ld=lld`) and prevents CMake from trying to run
cross-compiled binaries on the host. Passed on the command line with
`-DCMAKE_TOOLCHAIN_FILE=...`.

**Why `-fuse-ld=lld`?**
Without it, clang falls back to the host system `gcc` as the linker, which
rejects the 32-bit PowerPC target flags (`-m32` etc.) with an error. `-fuse-ld=lld`
tells clang to use LLD — LLVM's own architecture-agnostic linker — instead.

---

## Directory Structure

```
test_images/
├── CMakeLists.txt              ← root: project(), compile options,
│                                  ppe42_firmware() function, add_subdirectory()
├── cmake_build_readme.md       ← this file
├── cmake/
│   └── ppe42-clang.cmake       ← toolchain file (passed at configure time)
├── include/
│   └── target.h                ← shared memory-map constants (SRAM_START,
│                                  SRAM_LENGTH) used by C code and linker script
├── linker/
│   └── ppe42.ld                ← default linker script; #includes target.h
│                                  via the C preprocessor
├── kernel/
│   ├── CMakeLists.txt          ← defines 'kernel' static library target
│   ├── vectors.S               ← PPE42 exception/interrupt vector table
│   └── startup.s               ← C runtime entry: BSS clear, stack setup,
│                                  calls main()
├── lib/
│   └── printf/
│       ├── CMakeLists.txt      ← defines 'printf' static library target
│       ├── include/
│       │   └── printf.h        ← public API (propagated to consumers)
│       └── src/
│           └── printf.c        ← writes to memory-mapped output buffer;
│                                  advances write pointer to next d-word
│                                  (8-byte) aligned offset on each call
└── app/
    └── hello/
        ├── CMakeLists.txt      ← add_executable + ppe42_firmware() call
        └── main.c              ← calls printf("hello-world")
```

---

## Target Dependency Graph

```
         [kernel]  static library
         vectors.S + startup.s
         PRIVATE include: include/   (target.h — linker symbols only)
         no public headers
               │
               │ ppe42_firmware(KERNEL kernel)
               ▼
         [hello]  executable                [printf]  static library
               ◄──────────────────────────────────  printf.c
                  ppe42_firmware(LIBS printf)        PUBLIC include: lib/printf/include/
                                                     PRIVATE include: include/ (target.h)
               │
               ▼  POST_BUILD (in order)
         hello.dis  ← llvm-objdump -d -S --mcpu=ppe42
         hello.bin  ← llvm-objcopy -O binary
         hello.map  ← generated by ld.lld
```

---

## The `ppe42_firmware()` Function

Defined in the root `CMakeLists.txt`, this reusable function centralises
everything needed to turn an `add_executable()` target into a flashable PPE42
firmware image. Apps call it with their own specific choices — no other file
needs to change when a new combination is required.

```cmake
ppe42_firmware(<target>
    LINKER_SCRIPT <path>         # required — path to the linker script
    KERNEL        <target-name>  # required — which kernel variant to link
    LIBS          <t1> [t2 ...]  # optional — additional library targets
)
```

**What it does internally:**
1. `target_link_libraries(PRIVATE kernel libs...)` — links the chosen kernel and libraries
2. `target_link_options(...)` — applies `-fuse-ld=lld -T <script> --gc-sections`
3. POST_BUILD step 1 — `llvm-objdump` disassembles the ELF → `<target>.dis`
4. POST_BUILD step 2 — `llvm-objcopy` strips to raw binary → `<target>.bin`

**Example — future app with a different combination:**
```cmake
add_executable(myapp main.c)

ppe42_firmware(myapp
    LINKER_SCRIPT ${CMAKE_SOURCE_DIR}/linker/custom.ld
    KERNEL        kernel_v2
    LIBS          printf hal drivers
)
```

---

## Project-Wide Compile Flags

Set once in the root `CMakeLists.txt` via `add_compile_options()`. Every target
inherits them automatically — no target-level repetition needed.

| Flag | Purpose |
|------|---------|
| `-ffreestanding` | No host OS assumed; no implicit libc |
| `-fno-builtin` | Disable compiler built-in function substitutions |
| `-fno-stack-protector` | No stack canaries (no OS support) |
| `-fno-unwind-tables` | No exception unwind metadata |
| `-fno-asynchronous-unwind-tables` | No async unwind metadata |
| `-ffunction-sections` | Each function in its own section (enables `--gc-sections`) |
| `-fdata-sections` | Each variable in its own section (enables `--gc-sections`) |
| `-Wall -Wextra -Werror` | All warnings treated as errors |
| `-Wno-unused-command-line-argument` | Suppress clang noise for cross flags |

---

## Shared Memory Map (`include/target.h`)

```c
#define SRAM_START   0xFFF60000
#define SRAM_LENGTH  0x60000
```

These constants are defined once and shared between:
- **C source** — `printf.c` derives the output buffer address from `SRAM_START`
- **Linker script** — `ppe42.ld` includes `target.h` via `#include` (LLD
  preprocesses linker scripts before parsing them)

The output buffer used by `printf` is at:
```
SRAM_START + (0x400 * 16) = 0xFFF60000 + 0x4000 = 0xFFF64000
```

Each `printf` call writes at the current write pointer, then advances it to the
next **8-byte (d-word) aligned** offset so successive calls never overlap.

---

## Configure and Build

```bash
# From the test_images/ directory:

# Step 1 – Configure
cmake -S . -B build \
      -G Ninja \
      -DCMAKE_TOOLCHAIN_FILE=cmake/ppe42-clang.cmake

# Step 2 – Build
cmake --build build
```

| Flag | Meaning |
|------|---------|
| `-S .` | Source directory (where root `CMakeLists.txt` lives) |
| `-B build` | Build directory — generated files go here, source tree is never modified |
| `-G Ninja` | Use Ninja as the build tool (faster than Makefiles) |
| `-DCMAKE_TOOLCHAIN_FILE=...` | Path to the cross-compilation toolchain file |

---

## Output Artifacts

After a successful build the following files appear under `build/app/hello/`:

| File | Description |
|------|-------------|
| `hello` (ELF) | Linked ELF image — contains debug info and section headers |
| `hello.dis` | Disassembly of the ELF (generated before stripping) |
| `hello.bin` | Raw binary — ELF headers stripped, ready to flash |
| `hello.map` | Linker map — shows where every symbol was placed in memory |
