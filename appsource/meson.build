project(
  'llvm-sbe-apps',
  'c',
  version: '0.1.0',
  default_options: ['c_std=c99', 'warning_level=3', 'werror=true', 'optimization=2'],
)

fs = import('fs')
app_name = get_option('app')
app_dir = 'apps' / app_name
if not fs.is_dir(app_dir)
  error('Unknown application: ' + app_name)
endif

sbe_include = include_directories('include')
linker_script = meson.current_source_dir() / 'linker'

# Add shared modules here. Applications remain isolated under apps/<name>.
runtime_sources = files('runtime/format.c')
app_sources = files(app_dir / 'main.c')

firmware_objects = static_library(
  app_name + '-objects',
  files('vectors.S'),
  files('startup.s'),
  runtime_sources,
  app_sources,
  include_directories: sbe_include,
  c_args: [
    '-Wno-unused-command-line-argument',
    '-ffreestanding', '-fno-builtin', '-fno-stack-protector',
    '-fno-unwind-tables', '-fno-asynchronous-unwind-tables',
    '-ffunction-sections', '-fdata-sections',
  ],
  install: false,
)

ld_lld = find_program('/opt/llvm-install/bin/ld.lld')
llvm_objcopy = find_program('llvm-objcopy')
llvm_objdump = find_program('llvm-objdump')
llvm_nm = find_program('llvm-nm')

firmware = custom_target(
  app_name + '-elf',
  input: firmware_objects,
  output: app_name + '.elf',
  command: [
    ld_lld, '-T', linker_script, '--gc-sections',
    '-Map', app_name + '.map', '--whole-archive', '@INPUT@',
    '--no-whole-archive', '-o', '@OUTPUT@',
  ],
  depend_files: files('linker'),
  build_by_default: true,
)

custom_target(
  app_name + '-binary',
  input: firmware,
  output: app_name + '.bin',
  command: [llvm_objcopy, '-O', 'binary', '@INPUT@', '@OUTPUT@'],
  build_by_default: true,
)
custom_target(
  app_name + '-disassembly',
  input: firmware,
  output: app_name + '.dis',
  command: [llvm_objdump, '-d', '--mcpu=ppe42', '@INPUT@'],
  capture: true,
  build_by_default: true,
)
custom_target(
  app_name + '-symbols',
  input: firmware,
  output: app_name + '.symbols',
  command: [llvm_nm, '-n', '@INPUT@'],
  capture: true,
  build_by_default: true,
)
