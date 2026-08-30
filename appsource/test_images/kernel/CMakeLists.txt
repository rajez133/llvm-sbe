add_library(kernel STATIC
    vectors.S
    startup.s
)

# No public headers — kernel is linked in by executables but exposes
# no API to C code. The linker script symbols (_STACK, _VECTOR_START …)
# are resolved at link time, not via headers.
target_include_directories(kernel
    PRIVATE ${TEST_IMAGES_INCLUDE_DIR}
)
