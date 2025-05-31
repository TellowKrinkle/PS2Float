#include "ps2float.h"

#include <errno.h>
#include <fenv.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#pragma STDC FENV_ACCESS ON

typedef uint64_t u64;
typedef uint32_t u32;
typedef uint16_t u16;

static bool test_c;
static bool test_asm;
static bool test_sse4;
static bool test_avx;
static bool test_avx2;
static bool test_avx512f;

struct Test {
	u32 a;
	u32 b;
	u32 c;
};

struct UnaryTest {
	u32 in;
	u32 out;
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

static constexpr Test TESTS_DIV[] = {
	{0x3f800000, 0x3F800000, 0x3f800000},
	{0x3f800000, 0x7fffffff, 0x00000000},
	{0x3f800000, 0x00800000, 0x7e800000},
	{0x40000000, 0x00800000, 0x7f000000},
	{0x40800000, 0x00800000, 0x7f800000},
	{0x41000000, 0x00800000, 0x7fffffff},
	{0x40ffffff, 0x00800000, 0x7fffffff},
	{0x40fffffe, 0x00800000, 0x7ffffffe},
	{0x40ffffff, 0x7fffffff, 0x00800000},
	{0x40fffffe, 0x7fffffff, 0x00000000},
	{0x00000000, 0x00000000, 0x7fffffff},
	{0x007fffff, 0x007fffff, 0x7fffffff},
	{0x00800000, 0x007fffff, 0x7fffffff},
	{0x007fffff, 0x00800000, 0x00000000},
	{0x80000000, 0x80000000, 0x7fffffff},
	{0x007fffff, 0x807fffff, 0xffffffff},
	{0x80800000, 0x007fffff, 0xffffffff},
	{0x807fffff, 0x00800000, 0x80000000},
	{0x40000000, 0x3fb504f3, 0x3fb504f3},
	{0x40490fda, 0x3fb504f2, 0x400e2c19},
	{0x40490fda, 0x3fb504f3, 0x400e2c18},
	{0x40490fda, 0x3fb504f4, 0x400e2c18},
};

static constexpr UnaryTest TESTS_SQRT[] = {
	{0x3f800000, 0x3f800000},
	{0x7fffffff, 0x5fB504f3},
	{0xffffffff, 0x5fB504f3},
	{0x00800000, 0x20000000},
	{0x007fffff, 0x00000000},
	{0x807fffff, 0x00000000},
	{0x40000000, 0x3fb504f3},
	{0x40490fda, 0x3fe2dfc4},
	{0x40000001, 0x3fb504f4},
	{0x40000002, 0x3fb504f4},
	{0x40000003, 0x3fb504f5},
	{0x40000004, 0x3fb504f6},
	{0x40000005, 0x3fb504f6},
};

template <typename T>
struct ConstArrayRef {
	const T* begin_;
	size_t size_;
	const T* begin() const { return begin_; }
	const T* end()   const { return begin_ + size_; }
	size_t size()    const { return size_; }
	constexpr ConstArrayRef(const T* ptr, size_t size): begin_(ptr), size_(size) {}
	template <int N>
	constexpr ConstArrayRef(const T(&list)[N]): begin_(list), size_(N) {}
};

typedef ConstArrayRef<Test> TestList;
typedef ConstArrayRef<UnaryTest> UnaryTestList;

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

static bool run_tests(u32(*fn)(u32), UnaryTestList tests, const char* op, const char* name, bool printHeader, bool printSuccess) {
	if (printHeader)
		printf("Testing %s...\n", name);
	bool ok = true;
	for (const UnaryTest& test : tests) {
		uint32_t res = fn(test.in);
		ok &= res == test.out;
		if (res == test.out) {
			if (printSuccess)
				printf("%s(%08x) = %08x\n", op, test.in, res);
		} else {
			printf("%s(%08x) =[%s] %08x != %08x\n", op, test.in, name, res, test.out);
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
	if (test_c)
		ok &= run_tests(ps2add, tests, "+", "Accelerated Add C", print, print);
#ifdef __x86_64__
	if (test_asm)
		ok &= run_tests(ps2add_asm, tests, "+", "Accelerated Add ASM", print, false);
	if (test_avx2)
		ok &= run_tests(ps2add_avx2, tests, "+", "Accelerated Add AVX2", print);
	if (test_avx)
		ok &= run_tests(ps2add_avx,  tests, "+", "Accelerated Add AVX",  print);
	if (test_sse4)
		ok &= run_tests(ps2add_sse4, tests, "+", "Accelerated Add SSE4", print);
#endif
	fesetenv(&fenv);
	return ok;
}

static bool test_add_int(TestList tests, bool print) {
	bool ok = true;
	if (test_c)
		ok &= run_tests(ps2add_int, tests, "+", "Add C", print, false);
#ifdef __x86_64__
	if (test_asm)
		ok &= run_tests(ps2add_int_asm, tests, "+", "Add ASM", print, false);
	if (test_avx)
		ok &= run_tests(ps2add_int_avx, tests, "+", "Add AVX", print);
	if (test_sse4)
		ok &= run_tests(ps2add_int_sse4, tests, "+", "Add SSE4", print);
#endif
	return ok;
}

static bool test_mul(TestList tests, bool print) {
	bool ok = true;
	if (test_c) {
		ok &= run_tests(ps2mul, tests, "*", "Mul C", print, print);
		ok &= run_tests(ps2mul_swar, tests, "*", "Mul C SWAR", print, false);
	}
#ifdef __x86_64__
	if (test_asm)
		ok &= run_tests(ps2mul_asm, tests, "*", "Mul ASM", print, false);
	if (test_avx512f)
		ok &= run_tests(ps2mul_one_avx512, tests, "*", "Mul One AVX512", print);
	if (test_avx2) {
		ok &= run_tests(ps2mul_one_avx2, tests, "*", "Mul One AVX2", print);
		ok &= run_tests(ps2mul_avx2, tests, "*", "Mul AVX2", print);
	}
	if (test_avx) {
		ok &= run_tests(ps2mul_one_avx, tests, "*", "Mul One AVX", print);
		ok &= run_tests(ps2mul_avx, tests, "*", "Mul AVX", print);
	}
	if (test_sse4) {
		ok &= run_tests(ps2mul_one_sse4, tests, "*", "Mul One SSE4", print);
		ok &= run_tests(ps2mul_sse4, tests, "*", "Mul SSE4", print);
	}
#endif
	return ok;
}

static bool test_div(TestList tests, bool print) {
	bool ok = true;
	if (test_c)
		ok &= run_tests(ps2div, tests, "/", "Div C", print, print);
	return ok;
}

static bool test_sqrt(UnaryTestList tests, bool print) {
	bool ok = true;
	if (test_c)
		ok &= run_tests(ps2sqrt, tests, "sqrt", "Sqrt C", print, print);
	return ok;
}

/// Expand a 1-bit-per-test format where the one bit represents whether the given test rounded up or not
/// (Test is for mantissas only, so we just toss in a `0x3f800000` exponent to put them near 1)
static void expand_div_bit(Test* out, ConstArrayRef<u32> tests, u32* pdividend, u32* pdivisor) {
	u32 dividend = *pdividend;
	u32 divisor = *pdivisor;
	for (u32 test : tests) {
		for (u32 i = 0; i < 32; i++, dividend++) {
			u32 expected = static_cast<u32>((static_cast<u64>(dividend) << 24) / divisor);
			if (expected >= 1 << 24) {
				expected = (expected >> 1); // Upper 1 bit stays in exponent to turn 0x3f000000 to 0x3f800000
			} else {
				expected = (expected & 0x7fffff);
			}
			expected |= 0x3f000000;
			// Input data is one bit indicating if the PS2 rounded up
			// For exact results, the bit should be unset, so we can just add it
			expected += (test >> i) & 1;
			*out++ = { 0x3f800000 | dividend, 0x3f800000 | divisor, expected };
		}
		if (dividend == 1 << 24) {
			dividend = 1 << 23;
			divisor++;
		}
	}
	*pdividend = dividend;
	*pdivisor = divisor;
}

enum class Mode {
	Add,
	Mul,
	Div,
	DivBit,
	Sqrt,
};

static constexpr size_t getTestSize(Mode mode) {
	switch (mode) {
		case Mode::Add:
		case Mode::Mul:
		case Mode::Div:
			return sizeof(Test);
		case Mode::DivBit:
			return sizeof(uint32_t);
		case Mode::Sqrt:
			return sizeof(UnaryTest);
	}
}

static bool parseDivisor(u32* out, const char* str) {
	char* end;
	unsigned long res = strtoul(str, &end, 16);
	if (end == str) {
		fprintf(stderr, "%s is not a hex number\n", str);
		return false;
	}
	if (res < 0x800000) {
		fprintf(stderr, "Divisor %lx is too small (must be at least 0x800000)\n", res);
		return false;
	}
	if (res > 0xffffff) {
		fprintf(stderr, "Divisor %lx is too large (must be at most 0xffffff)\n", res);
		return false;
	}
	*out = static_cast<u32>(res);
	return true;
}

static bool ishex(char c) {
	if (c >= '0' && c <= '9')
		return true;
	if (c >= 'a' && c <= 'f')
		return true;
	if (c >= 'A' && c <= 'F')
		return true;
	return false;
}

static bool parseDivisorFromFilename(u32* out, const char* str) {
	const char* end = str + strlen(str);
	u32 numhex = 0;
	while (end > str) {
		--end;
		if (ishex(*end)) {
			if (++numhex == 6 && parseDivisor(out, end))
				return true;
		} else {
			numhex = 0;
		}
	}
	return false;
}

int main(int argc, const char * argv[]) {
	test_c = true;
#ifdef __x86_64__
	test_asm  = true;
	test_sse4 = __builtin_cpu_supports("sse4.1");
	test_avx  = __builtin_cpu_supports("avx");
	test_avx2 = __builtin_cpu_supports("avx2");
	test_avx512f = __builtin_cpu_supports("avx512f");
#endif

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
		} else if (0 == strcasecmp(argv[1], "div")) {
			mode = Mode::Div;
		} else if (0 == strcasecmp(argv[1], "divbit")) {
			mode = Mode::DivBit;
		} else if (0 == strcasecmp(argv[1], "sqrt")) {
			mode = Mode::Sqrt;
		} else {
			fprintf(stderr, "Unrecognized test mode %s\n", argv[1]);
			return EXIT_FAILURE;
		}

		constexpr size_t maxtests = 65536;
		void* buffer = malloc(getTestSize(mode) * maxtests);
		Test* expand = nullptr;
		if (mode == Mode::DivBit) {
			expand = static_cast<Test*>(malloc(sizeof(Test) * maxtests * 32));
		}
		u64 total = 0;
		bool startOverride = false;
		u32 dividend = 0x800000;
		u32 divisor = 0x800000;
		for (int i = 2; i < argc; i++) {
			bool useStdin = 0 == strcmp(argv[i], "-");

			if (0 == strcasecmp(argv[i], "--no-c")) {
				test_c = false;
				continue;
			} else if (0 == strcasecmp(argv[i], "--no-asm")) {
				test_asm = false;
				continue;
			} else if (0 == strcasecmp(argv[i], "--no-sse4")) {
				test_sse4 = false;
				continue;
			} else if (0 == strcasecmp(argv[i], "--no-avx")) {
				test_avx = false;
				continue;
			} else if (0 == strcasecmp(argv[i], "--no-avx2")) {
				test_avx2 = false;
				continue;
			} else if (0 == strcasecmp(argv[i], "--no-avx512")) {
				test_avx512f = false;
				continue;
			}

			if (mode == Mode::DivBit && i + 1 < argc && 0 == strcasecmp(argv[i], "--start")) {
				if (parseDivisor(&divisor, argv[i + 1])) {
					i += 1;
					dividend = 0x800000;
					startOverride = true;
					continue;
				}
			}
			if (mode == Mode::DivBit && !startOverride) {
				if (parseDivisorFromFilename(&divisor, argv[i]))
					dividend = 0x800000;
			}

			FILE* file = useStdin ? stdin : fopen(argv[i], "r");
			if (!file) {
				fprintf(stderr, "Failed to open %s for reading: %s\n", argv[i], strerror(errno));
				continue;
			}
			while (true) {
				size_t ntests = fread(buffer, getTestSize(mode), maxtests, file);
				if (ntests == 0)
					break;
				total += ntests;
				TestList tests = TestList(static_cast<Test*>(buffer), ntests);
				UnaryTestList unaryTests = UnaryTestList(static_cast<UnaryTest*>(buffer), ntests);
				switch (mode) {
					case Mode::Add:
						ok &= test_add(tests, false);
						ok &= test_add_int(tests, false);
						break;
					case Mode::Mul:
						ok &= test_mul(tests, false);
						break;
					case Mode::Div:
						ok &= test_div(tests, false);
						break;
					case Mode::DivBit:
						expand_div_bit(expand, ConstArrayRef<u32>(static_cast<u32*>(buffer), ntests), &dividend, &divisor);
						ok &= test_div(TestList(expand, ntests * 32), false);
						break;
					case Mode::Sqrt:
						ok &= test_sqrt(unaryTests, false);
						break;
				}
			}
			if (ferror(file))
				fprintf(stderr, "Failed to read file %s: %s\n", argv[i], strerror(ferror(file)));
			if (!useStdin)
				fclose(file);
		}
		free(buffer);
		if (expand)
			free(expand);
		if (mode == Mode::DivBit)
			total *= 32;
		printf("Ran %lld tests\n", total);
	} else {
		ok &= test_add(TESTS_ADD, true);
		ok &= test_add_int(TESTS_ADD, true);
		ok &= test_mul(TESTS_MUL, true);
		ok &= test_div(TESTS_DIV, true);
		ok &= test_sqrt(TESTS_SQRT, true);
	}
	if (ok)
		puts("All Pass");
	return ok ? EXIT_SUCCESS : EXIT_FAILURE;
}
