add_library(printf STATIC
    src/printf.c
)

# printf.h is PUBLIC: any target linking this library automatically gets
# the include path without repeating it.
# target.h is PRIVATE: it is an internal implementation detail.
target_include_directories(printf
    PUBLIC  include
    PRIVATE ${TEST_IMAGES_INCLUDE_DIR}
)
