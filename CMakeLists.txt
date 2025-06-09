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
	ps2divsqrt.cpp
	ps2divsqrt-x86_64.S
)
target_compile_features(ps2float PRIVATE cxx_std_20)

add_executable(ps2float-tests
	main.cpp
)
target_link_libraries(ps2float-tests PRIVATE ps2float)
target_compile_features(ps2float-tests PRIVATE cxx_std_20)

if (APPLE)
	find_library(METAL Metal)
	find_library(FOUNDATION Foundation)
	add_executable(ps2float-divtest-metal test-div-metal.mm)
	target_link_libraries(ps2float-divtest-metal PRIVATE ${METAL} ${FOUNDATION})
	target_compile_options(ps2float-divtest-metal PRIVATE -fobjc-arc)
	target_link_options(ps2float-divtest-metal PRIVATE -fobjc-arc)
	target_compile_features(ps2float-divtest-metal PRIVATE cxx_std_11)
	target_compile_definitions(ps2float-divtest-metal PRIVATE "DIV_SQRT_FILE_PATH=\"${CMAKE_CURRENT_SOURCE_DIR}/ps2divsqrt.cpp\"")
	# We incbin ps2divsqrt.cpp, which isn't picked up by cmake
	set_property(SOURCE test-div-metal.mm APPEND PROPERTY OBJECT_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/ps2divsqrt.cpp")
endif()
