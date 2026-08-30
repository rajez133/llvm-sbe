# Toolchain file for PPE42 cross-compilation using the in-tree clang/lld.
# Usage:
#   cmake -DCMAKE_TOOLCHAIN_FILE=cmake/ppe42-clang.cmake ...

set(CMAKE_SYSTEM_NAME      Generic)
set(CMAKE_SYSTEM_PROCESSOR powerpc)

set(LLVM_INSTALL "/opt/llvm-install")

set(CMAKE_C_COMPILER   "${LLVM_INSTALL}/bin/clang")
set(CMAKE_AR           "${LLVM_INSTALL}/bin/llvm-ar"     CACHE FILEPATH "Archiver")
set(CMAKE_RANLIB       "${LLVM_INSTALL}/bin/llvm-ranlib"  CACHE FILEPATH "Ranlib")
set(CMAKE_STRIP        "${LLVM_INSTALL}/bin/llvm-strip"   CACHE FILEPATH "Strip")
set(CMAKE_OBJCOPY      "${LLVM_INSTALL}/bin/llvm-objcopy" CACHE FILEPATH "Objcopy")
set(CMAKE_OBJDUMP      "${LLVM_INSTALL}/bin/llvm-objdump" CACHE FILEPATH "Objdump")
set(CMAKE_LINKER       "${LLVM_INSTALL}/bin/ld.lld"       CACHE FILEPATH "Linker")

# Compiler target flags applied to every compile invocation.
set(TARGET_FLAGS "-target powerpc-unknown-elf -mcpu=ppe42 -msoft-float")

set(CMAKE_C_FLAGS_INIT   "${TARGET_FLAGS}" CACHE STRING "")
set(CMAKE_ASM_FLAGS_INIT "${TARGET_FLAGS}" CACHE STRING "")

# Override the link rule so CMake calls ld.lld directly instead of routing
# through clang.  When clang drives linking it passes -m32 to the system gcc
# linker (which is x86-64 and rejects it).  Calling ld.lld directly avoids
# that entirely — ld.lld is architecture-agnostic and needs no -m32 flag.
#
# CMake link rule placeholders:
#   <CMAKE_C_COMPILER>  — the compiler (used here as the object supplier)
#   <LINK_FLAGS>        — flags from target_link_options / CMAKE_EXE_LINKER_FLAGS
#   <OBJECTS>           — compiled .o files
#   <TARGET>            — output file
#   <LINK_LIBRARIES>    — resolved library paths
set(CMAKE_C_LINK_EXECUTABLE
    "${LLVM_INSTALL}/bin/ld.lld <LINK_FLAGS> <OBJECTS> -o <TARGET> <LINK_LIBRARIES>"
)

# Do not try to run cross-compiled binaries on the host.
set(CMAKE_CROSSCOMPILING TRUE)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
