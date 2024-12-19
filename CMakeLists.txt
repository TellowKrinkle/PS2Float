cmake_minimum_required(VERSION 3.10...3.25)
project(ps2float LANGUAGES CXX ASM)

add_executable(ps2float-tests
	ps2add.cpp
	ps2add.S
)
target_compile_features(ps2float-tests PRIVATE cxx_std_20)
