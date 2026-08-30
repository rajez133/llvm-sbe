cmake_minimum_required(VERSION 3.20)

project(ppe42-test-images LANGUAGES C ASM)

# ---------------------------------------------------------------------------
# Paths shared across the whole project
# ---------------------------------------------------------------------------
set(TEST_IMAGES_INCLUDE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/include)

find_program(LLVM_OBJCOPY  llvm-objcopy  PATHS /opt/llvm-install/bin REQUIRED)
find_program(LLVM_OBJDUMP  llvm-objdump  PATHS /opt/llvm-install/bin REQUIRED)
find_program(CPP_PREPROCESSOR cpp REQUIRED)

# ---------------------------------------------------------------------------
# Project-wide compile options — inherited by every target in the build.
# Mirror the flags used in the meson cross build.
# ---------------------------------------------------------------------------
add_compile_options(
    -ffreestanding
    -fno-builtin
    -fno-stack-protector
    -fno-unwind-tables
    -fno-asynchronous-unwind-tables
    -ffunction-sections
    -fdata-sections
    -Wall
    -Wextra
    -Werror
    -Wno-unused-command-line-argument
)

# ---------------------------------------------------------------------------
# ppe42_firmware(<target>
#     LINKER_SCRIPT        <path>         # required — app-specific linker script
#     KERNEL               <target>       # required — kernel variant to link
#     LIBS                 <t1> [t2 ...]  # optional — additional library targets
#     LINKER_INCLUDE_DIRS  <d1> [d2 ...]  # optional — include dirs for linker
#                                         #   script preprocessing (e.g. for
#                                         #   #include "target.h")
# )
#
# 1. Preprocesses the linker script via clang -E -P, writing the result to
#    the build directory so #include directives in the script are resolved.
# 2. Links the chosen kernel and library targets into <target>.
# 3. Applies standard PPE42 link flags (lld + preprocessed linker script).
# 4. POST_BUILD step 1: disassemble the ELF  → <target>.dis
# 5. POST_BUILD step 2: strip the ELF        → <target>.bin
#
# Each app declares its own combination of kernel and libs, so different
# images can mix different variants without touching the root file.
# ---------------------------------------------------------------------------
function(ppe42_firmware TARGET)
    cmake_parse_arguments(ARG "" "LINKER_SCRIPT;KERNEL" "LIBS;LINKER_INCLUDE_DIRS" ${ARGN})

    if(NOT ARG_LINKER_SCRIPT)
        message(FATAL_ERROR "ppe42_firmware(${TARGET}): LINKER_SCRIPT is required")
    endif()
    if(NOT ARG_KERNEL)
        message(FATAL_ERROR "ppe42_firmware(${TARGET}): KERNEL is required")
    endif()

    # --- Preprocess linker script -------------------------------------------
    # clang -E -P runs the C preprocessor (-E) and suppresses #line markers
    # (-P) so ld.lld receives a clean linker script with all #include
    # directives and macros fully expanded.
    set(LD_SCRIPT_PP ${CMAKE_CURRENT_BINARY_DIR}/${TARGET}.ld)

    # Build -I flags for each supplied include directory.
    set(LD_INCLUDE_FLAGS "")
    foreach(DIR ${ARG_LINKER_INCLUDE_DIRS})
        list(APPEND LD_INCLUDE_FLAGS -I${DIR})
    endforeach()

    add_custom_command(
        OUTPUT  ${LD_SCRIPT_PP}
        COMMAND ${CPP_PREPROCESSOR}
                -P                          # suppress #line markers
                ${LD_INCLUDE_FLAGS}
                ${ARG_LINKER_SCRIPT}
                -o ${LD_SCRIPT_PP}
        DEPENDS ${ARG_LINKER_SCRIPT}        # re-run if the script changes
        COMMENT "Preprocessing linker script → ${TARGET}.ld"
    )

    # Make the executable depend on the preprocessed script so it is
    # generated before the link step runs.
    add_custom_target(${TARGET}-ld-pp DEPENDS ${LD_SCRIPT_PP})
    add_dependencies(${TARGET} ${TARGET}-ld-pp)

    # --- Wire up kernel + optional libraries --------------------------------
    target_link_libraries(${TARGET} PRIVATE ${ARG_KERNEL} ${ARG_LIBS})

    # --- Link flags ---------------------------------------------------------
    # Flags are passed directly to ld.lld (not through the clang driver),
    # so the -Wl, prefix must NOT be used — ld.lld takes flags without it.
    target_link_options(${TARGET} PRIVATE
        -T ${LD_SCRIPT_PP}
        --gc-sections
        --Map=${CMAKE_CURRENT_BINARY_DIR}/${TARGET}.map
    )

    # --- POST_BUILD step 1: disassembly (from ELF, before stripping) --------
    add_custom_command(TARGET ${TARGET} POST_BUILD
        COMMAND ${LLVM_OBJDUMP}
                -d -S --mcpu=ppe42
                $<TARGET_FILE:${TARGET}>
                > $<TARGET_FILE_DIR:${TARGET}>/${TARGET}.dis
        COMMENT "Disassembling ${TARGET}.elf → ${TARGET}.dis"
    )

    # --- POST_BUILD step 2: raw binary (strip ELF headers) ------------------
    add_custom_command(TARGET ${TARGET} POST_BUILD
        COMMAND ${LLVM_OBJCOPY}
                -O binary
                $<TARGET_FILE:${TARGET}>
                $<TARGET_FILE_DIR:${TARGET}>/${TARGET}.bin
        COMMENT "Generating ${TARGET}.bin"
    )
endfunction()

# ---------------------------------------------------------------------------
# Subdirectories
# ---------------------------------------------------------------------------
add_subdirectory(kernel)
add_subdirectory(lib/printf)
add_subdirectory(app/hello)
