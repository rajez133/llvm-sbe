# PPE42 application framework

The image is split into four layers:

- `vectors.S` contains the fixed exception table; `startup.s` contains the freestanding reset path.
- `runtime/` contains facilities shared by every image.
- `include/sbe/` is the runtime/module public API.
- `apps/<name>/` contains one `main` and its application-specific modules.

Configure, test, and build the default hello image inside the LLVM development
container with:

```sh
meson setup output/meson-hello --cross-file cross/ppe42.ini -Dapp=hello
meson test -C output/meson-hello --print-errorlogs
meson compile -C output/meson-hello
```

Select another application by changing `-Dapp=name` and using a separate build
directory. Shared modules are listed in `runtime_sources` in `meson.build`;
applications live in separate `apps/name` directories. Each build produces an ELF,
flat binary, map, disassembly, and symbol file in its Meson build directory.

The hello smoke test copies `Hello world` into `sbe_test_output` and
stores the snprintf return value in `sbe_test_output_length`. Their SRAM addresses
are in `output/meson-hello/hello.symbols`, allowing a simulator or debugger to inspect the
result without requiring a console device.

For now, `sbe_snprintf` is deliberately just a bounded string copy. It returns the
source length and always NUL-terminates a non-empty destination. Formatting can be
introduced later when an application actually needs it.
