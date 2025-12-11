cmake_minimum_required(VERSION 3.18.1)
project(native-lib)

find_library(BZ2_LIB bz2)

add_library(
    native-lib
    SHARED
    native-lib.cc
    bspatch.c
    bzip2/blocksort.c
    bzip2/huffman.c
    bzip2/crctable.c
    bzip2/randtable.c
    bzip2/compress.c
    bzip2/decompress.c
    bzip2/bzlib.c
)

target_include_directories(native-lib PRIVATE ${CMAKE_SOURCE_DIR}/bzip2)

find_library(log-lib log)

target_link_libraries(
    native-lib
    log
)
