add_executable(hello
    main.c
)

# Declare which kernel variant and libraries this image uses.
# To use a different combination, change the values here without
# touching any other file in the project.
ppe42_firmware(hello
    LINKER_SCRIPT       ${CMAKE_SOURCE_DIR}/linker/ppe42.ld
    LINKER_INCLUDE_DIRS ${CMAKE_SOURCE_DIR}/include
    KERNEL              kernel
    LIBS                printf
)
