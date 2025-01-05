#include "ps2float.h"

#include <errno.h>
#include <fenv.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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
	{ 0x0a7ffff8, 0x8a800001, 0x80000000 },
	{ 0x3f800000, 0x9d19cd52, 0x3f800000 },
	{ 0x3f800000, 0xb3abd455, 0x3f7fffff },
	{ 0x3f800002, 0xb3800000, 0x3f800001 },
};

static constexpr Test TESTS_MUL[] = {
	{ 0x3f800000, 0x3f800000, 0x3f800000 },
	{ 0x3f800000, 0x3f800002, 0x3f800001 },
	{ 0x43480000, 0x43480000, 0x471c4000 },
	{ 0x7fffffff, 0x7fffffff, 0x7fffffff },
	{ 0x7fffffff, 0xffffffff, 0xffffffff },
	{ 0xffffffff, 0x7fffffff, 0xffffffff },
	{ 0xffffffff, 0xffffffff, 0x7fffffff },
	{ 0x7fffffff, 0x00000000, 0x00000000 },
	{ 0x007fffff, 0x7fffffff, 0x00000000 },
	{ 0x7fffffff, 0x007fffff, 0x00000000 },
	{ 0x00800000, 0x7fffffff, 0x40fffffe },
	{ 0x7fffffff, 0x00800000, 0x40ffffff },
	{ 0x7f800000, 0x7f800000, 0x7fffffff },
	{ 0x3f9e4791, 0x7f800000, 0x7f9e4791 },
	{ 0x3f800400, 0x3f800001, 0x3f800401 },
	{ 0x3f800400, 0x3f800002, 0x3f800401 },
	{ 0x3faaab00, 0x3f800003, 0x3faaab03 },
	{ 0x408f0000, 0x7e8fffff, 0x7fa0dffe },
	{ 0x40cf0000, 0x7ecfffff, 0x7fffffff },
	{ 0x3f480000, 0x00c80000, 0x009c4000 },
	{ 0x3f080000, 0x00c80000, 0x00000000 },
};

struct TestList {
	const Test* begin_;
	const Test* end_;
	const Test* begin() const { return begin_; }
	const Test* end()   const { return end_; }
	constexpr TestList(const Test* ptr, size_t size): begin_(ptr), end_(ptr + size) {}
	template <int N>
	constexpr TestList(const Test(&list)[N]): begin_(list), end_(list + N) {}
};

static bool run_tests(u32(*fn)(u32, u32), TestList tests, const char* op, const char* name, bool printHeader, bool printSuccess) {
	if (printHeader)
		printf("Testing %s...\n", name);
	bool ok = true;
	for (const Test& test : tests) {
		uint32_t res = fn(test.a, test.b);
		ok &= res == test.c;
		if (res == test.c) {
			if (printSuccess)
				printf("%08x %s %08x = %08x\n", test.a, op, test.b, res);
		} else {
			printf("%08x %s %08x =[%s] %08x != %08x\n", test.a, op, test.b, name, res, test.c);
		}
	}
	return ok;
}

#ifdef __x86_64__
static bool run_tests(__m128i(*fn)(__m128i, __m128i), TestList tests, const char* op, const char* name, bool printHeader) {
	if (printHeader)
		printf("Testing %s...\n", name);
	bool ok = true;
	for (const Test& test : tests) {
		__m128i a = _mm_set1_epi32(test.a);
		__m128i b = _mm_set1_epi32(test.b);
		__m128i res = fn(a, b);
		u16 alleq = ~_mm_movemask_epi8(_mm_cmpeq_epi32(res, _mm_shuffle_epi32(res, 0)));
		u32 res32 = _mm_cvtsi128_si32(res);
		ok &= alleq == 0 && res32 == test.c;
		if (alleq != 0) {
			printf("Not all vectors matched when testing %08x %s %08x\n", test.a, op, test.b);
		} else if (res32 != test.c) {
			printf("%08x %s %08x =[%s] %08x != %08x\n", test.a, op, test.b, name, res32, test.c);
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
#elif defined(__aarch64__)
	u32 fpcr;
	asm volatile("mrs %x[fpcr], FPCR" : [fpcr]"=r"(fpcr));
	fpcr |= 1 << 24;
	asm volatile("msr FPCR, %x[fpcr]" :: [fpcr]"r"(fpcr));
#else
	#warning "Can't disable denormals"
#endif
	fesetround(FE_TOWARDZERO);
}

static bool test_add(TestList tests, bool print) {
	fenv_t fenv;
	fegetenv(&fenv);
	setup_fenv();
	bool ok = true;
	ok &= run_tests(ps2add, tests, "+", "Accelerated Add C", print, print);
#ifdef __x86_64__
	ok &= run_tests(ps2add_asm, tests, "+", "Accelerated Add ASM", print, false);
	if (__builtin_cpu_supports("avx2"))
		ok &= run_tests(ps2add_avx2, tests, "+", "Accelerated Add AVX2", print);
	if (__builtin_cpu_supports("avx"))
		ok &= run_tests(ps2add_avx,  tests, "+", "Accelerated Add AVX",  print);
	if (__builtin_cpu_supports("sse4.1"))
		ok &= run_tests(ps2add_sse4, tests, "+", "Accelerated Add SSE4", print);
#endif
	fesetenv(&fenv);
	return ok;
}

static bool test_add_int(TestList tests, bool print) {
	bool ok = true;
	ok &= run_tests(ps2add_int, tests, "+", "Add C", print, false);
#ifdef __x86_64__
	ok &= run_tests(ps2add_int_asm, tests, "+", "Add ASM", print, false);
	if (__builtin_cpu_supports("avx"))
		ok &= run_tests(ps2add_int_avx, tests, "+", "Add AVX", print);
	if (__builtin_cpu_supports("sse4.1"))
		ok &= run_tests(ps2add_int_sse4, tests, "+", "Add SSE4", print);
#endif
	return ok;
}

static bool test_mul(TestList tests, bool print) {
	bool ok = true;
	ok &= run_tests(ps2mul, tests, "*", "Mul C", print, print);
#ifdef __x86_64__
	ok &= run_tests(ps2mul_asm, tests, "*", "Mul ASM", print, false);
	if (__builtin_cpu_supports("avx2"))
		ok &= run_tests(ps2mul_one_avx2, tests, "*", "Mul One AVX2", print);
#endif
	return ok;
}

enum class Mode {
	Add,
	Mul,
};

int main(int argc, const char * argv[]) {
	bool ok = true;
	if (argc > 1) {
		if (argc <= 2) {
			fprintf(stderr, "Usage: %s operation file [file...]\n", argv[0]);
			return EXIT_FAILURE;
		}
		Mode mode;
		if (0 == strcasecmp(argv[1], "add")) {
			mode = Mode::Add;
		} else if (0 == strcasecmp(argv[1], "mul")) {
			mode = Mode::Mul;
		} else {
			fprintf(stderr, "Unrecognized test mode %s\n", argv[1]);
			return EXIT_FAILURE;
		}

		constexpr size_t maxtests = 65536;
		Test* buffer = static_cast<Test*>(malloc(sizeof(Test) * maxtests));
		uint64_t total = 0;
		for (int i = 2; i < argc; i++) {
			bool useStdin = 0 == strcmp(argv[i], "-");
			FILE* file = useStdin ? stdin : fopen(argv[i], "r");
			if (!file) {
				fprintf(stderr, "Failed to open %s for reading: %s\n", argv[i], strerror(errno));
				continue;
			}
			while (true) {
				size_t ntests = fread(buffer, sizeof(Test), maxtests, file);
				if (ntests == 0)
					break;
				total += ntests;
				TestList tests = TestList(buffer, ntests);
				switch (mode) {
					case Mode::Add:
						ok &= test_add(tests, false);
						ok &= test_add_int(tests, false);
						break;
					case Mode::Mul:
						ok &= test_mul(tests, false);
						break;
				}
			}
			if (ferror(file))
				fprintf(stderr, "Failed to read file %s: %s\n", argv[i], strerror(ferror(file)));
			if (!useStdin)
				fclose(file);
			free(buffer);
		}
		printf("Ran %lld tests\n", total);
	} else {
		ok &= test_add(TESTS_ADD, true);
		ok &= test_add_int(TESTS_ADD, true);
		ok &= test_mul(TESTS_MUL, true);
	}
	if (ok)
		puts("All Pass");
	return ok ? EXIT_SUCCESS : EXIT_FAILURE;
}
