#include "ps2float.h"

#include <stdio.h>
#include <stdlib.h>
#include <fenv.h>

#pragma STDC FENV_ACCESS ON

typedef uint32_t u32;
typedef uint16_t u16;

struct Test {
	u32 a;
	u32 b;
	u32 c;
};

static constexpr Test TESTS_ADD[] = {
	{ 0x3f800000, 0xbcf776f9, 0x3f784449 },
	{ 0x7f7fffff, 0x7fffffff, 0x7fffffff },
	{ 0x7ffddddd, 0xb4480000, 0x7ffddddd },
	{ 0x7ffddddd, 0xff800000, 0x7f7bbbba },
	{ 0xf4800000, 0x7ffddddd, 0x7ffddddb },
	{ 0x7ffddddd, 0x7ffddddd, 0x7fffffff },
	{ 0x7fffffff, 0xffffffff, 0x00000000 },
	{ 0x80000000, 0x80000000, 0x80000000 },
	{ 0x80000000, 0x00000000, 0x00000000 },
	{ 0x00000000, 0x80000000, 0x00000000 },
	{ 0x007fffff, 0x007fffff, 0x00000000 },
	{ 0x807fffff, 0x807fffff, 0x80000000 },
	{ 0x807fffff, 0x00000001, 0x00000000 },
	{ 0x0c800000, 0x8c7fffff, 0x00800000 },
	{ 0x0c000000, 0x8bffffff, 0x00000000 },
	{ 0x0c7fffff, 0x8c800000, 0x80800000 },
	{ 0x0bffffff, 0x8c000000, 0x80000000 },
	{ 0x3f800000, 0x9d19cd52, 0x3f800000 },
	{ 0x3f800000, 0xb3abd455, 0x3f7fffff },
	{ 0x3f800002, 0xb3800000, 0x3f800001 },
};

static bool run_tests(u32(*fn)(u32, u32), const char* name, bool printSuccess) {
	printf("Testing %s...\n", name);
	bool ok = true;
	for (const Test& test : TESTS_ADD) {
		uint32_t res = fn(test.a, test.b);
		ok &= res == test.c;
		if (res == test.c) {
			if (printSuccess)
				printf("%08x + %08x = %08x\n", test.a, test.b, res);
		} else {
			printf("%08x + %08x =[%s] %08x != %08x\n", test.a, test.b, name, res, test.c);
		}
	}
	return ok;
}

#ifdef __x86_64__
static bool run_tests(__m128i(*fn)(__m128i, __m128i), const char* name) {
	printf("Testing %s...\n", name);
	bool ok = true;
	for (const Test& test : TESTS_ADD) {
		__m128i a = _mm_set1_epi32(test.a);
		__m128i b = _mm_set1_epi32(test.b);
		__m128i res = fn(a, b);
		u16 alleq = ~_mm_movemask_epi8(_mm_cmpeq_epi32(res, _mm_shuffle_epi32(res, 0)));
		u32 res32 = _mm_cvtsi128_si32(res);
		ok &= alleq == 0 && res32 == test.c;
		if (alleq != 0) {
			printf("Not all vectors matched when testing %08x + %08x\n", test.a, test.b);
		} else if (res32 != test.c) {
			printf("%08x + %08x =[%s] %08x != %08x\n", test.a, test.b, name, res32, test.c);
		}
	}
	return ok;
}
#endif

/// Set up fenv for PS2-on-IEEE emulation
static void setup_fenv() {
#if defined(FE_DFL_DISABLE_SSE_DENORMS_ENV)
	fesetenv(FE_DFL_DISABLE_SSE_DENORMS_ENV);
#elif defined(FE_DFL_DISABLE_DENORMS_ENV)
	fesetenv(FE_DFL_DISABLE_DENORMS_ENV);
#elif defined(__x86_64__)
	_MM_SET_FLUSH_ZERO_MODE(_MM_FLUSH_ZERO_ON);
	_MM_SET_DENORMALS_ZERO_MODE(_MM_DENORMALS_ZERO_ON);
#else
	#warning Can't disable denormals
#endif
	fesetround(FE_TOWARDZERO);
}

static bool test_add() {
	fenv_t fenv;
	fegetenv(&fenv);
	setup_fenv();
	bool ok = true;
	ok &= run_tests(ps2add, "Accelerated Add C", true);
#ifdef __x86_64__
	ok &= run_tests(ps2add_asm, "Accelerated Add ASM", false);
	if (__builtin_cpu_supports("avx2"))
		ok &= run_tests(ps2add_avx2, "Accelerated Add AVX2");
	if (__builtin_cpu_supports("avx"))
		ok &= run_tests(ps2add_avx,  "Accelerated Add AVX");
	if (__builtin_cpu_supports("sse4.1"))
		ok &= run_tests(ps2add_sse4, "Accelerated Add SSE4");
#endif
	fesetenv(&fenv);
	return ok;
}

static bool test_add_int() {
	bool ok = true;
	ok &= run_tests(ps2add_int, "Add C", false);
#ifdef __x86_64__
	ok &= run_tests(ps2add_int_asm, "Add ASM", false);
#endif
	return ok;
}

int main(int argc, const char * argv[]) {
	bool ok = true;
	ok &= test_add();
	ok &= test_add_int();
	if (ok)
		puts("All Pass");
	return ok ? EXIT_SUCCESS : EXIT_FAILURE;
}
