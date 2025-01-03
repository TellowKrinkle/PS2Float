cmake_minimum_required(VERSION 3.10...3.25)
project(ps2float LANGUAGES CXX ASM)

if(MSVC)
	message(FATAL_ERROR "This project only supports GCC and Clang")
endif()

add_library(ps2float
	ps2float.h
	ps2add.cpp
	ps2add-x86_64.S
	ps2mul.cpp
	ps2mul-x86_64.S
)
target_compile_features(ps2float PRIVATE cxx_std_20)

add_executable(ps2float-tests
	main.cpp
)
target_link_libraries(ps2float-tests PRIVATE ps2float)
target_compile_features(ps2float-tests PRIVATE cxx_std_20)
