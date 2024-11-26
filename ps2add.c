#include <stdio.h>
#include <fenv.h>
#include <stdint.h>
#include <algorithm>

#pragma STDC FENV_ACCESS ON

typedef uint8_t u8;
typedef uint16_t u16;
typedef uint32_t u32;
typedef  int32_t s32;
typedef  int16_t s16;

#ifdef __x86_64__
#include <immintrin.h>
extern "C" u32 ps2add_asm(u32 a, u32 b);
extern "C" __m128i ps2add_avx2(__m128i a, __m128i b);
extern "C" __m128i ps2add_avx(__m128i a, __m128i b);
extern "C" __m128i ps2add_sse4(__m128i a, __m128i b);
#endif

u32 ps2add(u32 a, u32 b) {
	if ((a & 0x7fffffff) < (b & 0x7fffffff))
		std::swap(a, b); // Make a the larger of the two
	u8 aexp = ((a >> 23) & 0xff);
	u8 bexp = ((b >> 23) & 0xff);
	u8 shift = aexp - bexp;
	// We don't want the exponent to reach 255 after adding, since this would clamp to INF on IEEE
	// Adding two numbers with exponent 254 could end with an exponent 255, so adjust for either of those cases
	u32 adjust = aexp > 253 ? (2 << 23) : 0;
	a -= adjust;
	b -= adjust; // Don't worry about underflowing, if b is that much lower than a it'll get cleared to zero
	if (shift > 24)
		b &= 0x80000000; // All bits gone, b => ±0
	else if (shift > 1)
		b &= ~0u << (shift - 1);
	u32 res = std::bit_cast<u32>(std::bit_cast<float>(a) + std::bit_cast<float>(b));
	u32 adjusted = res + adjust;
	if (static_cast<s32>(adjusted ^ res) < 0) // Did adding the adjustment overflow?
		res |= 0x7fffffff;
	else if (res)
		res = adjusted;
	return res;
}

/// ps2add without using fp adder and relying on setting ftz, daz, and round towards zero
u32 ps2add_int(u32 a, u32 b) {
	static constexpr u32 SIGN = 0x80000000;
	if ((a & 0x7fffffff) < (b & 0x7fffffff))
		std::swap(a, b); // Make a the larger of the two
	u8 aexp = ((a >> 23) & 0xff);
	u8 bexp = ((b >> 23) & 0xff);
	if (!bexp)
		return aexp ? a : a & b & SIGN;
	if (a == (b ^ SIGN))
		return 0;
	u8 shift = aexp - bexp;
	u32 amant = ((a & 0x7fffff) | 0x800000) << 1;
	u32 bmant = ((b & 0x7fffff) | 0x800000) << 1;
	if (shift > 24)
		bmant = 0;
	else
		bmant >>= shift;
	s32 negate = static_cast<s32>(a ^ b) >> 31;
	bmant ^= negate;
	bmant -= negate; // Conditionally negate b if it's the opposite sign of a
	amant += bmant;
	u32 lz = __builtin_clz(amant);
	amant <<= lz;
	amant >>= 31 - 23;
	s32 cexp = aexp + (7 - lz);
	if (cexp <= 0)
		return a & SIGN;
	if (cexp > 255)
		return a | 0x7fffffff;
	return (a & SIGN) | (cexp << 23) | (amant & 0x7fffff);
}

u32 ps2sub(u32 a, u32 b) {
	return ps2add(a, b ^ 0x80000000);
}

static constexpr struct Test {
	uint32_t a;
	uint32_t b;
	uint32_t c;
} tests[] = {
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
};

static bool run_tests(u32(*fn)(u32, u32), const char* name) {
	bool ok = true;
	for (const Test& test : tests) {
		uint32_t res = fn(test.a, test.b);
		ok &= res == test.c;
		if (res == test.c)
			printf("%08x + %08x =[%s] %08x\n", test.a, test.b, name, res);
		else
			printf("%08x + %08x =[%s] %08x != %08x\n", test.a, test.b, name, res, test.c);
	}
	return ok;
}

#ifdef __x86_64__
static bool run_tests(__m128i(*fn)(__m128i, __m128i), const char* name) {
	bool ok = true;
	for (const Test& test : tests) {
		__m128i a = _mm_set1_epi32(test.a);
		__m128i b = _mm_set1_epi32(test.b);
		__m128i res = fn(a, b);
		u16 alleq = ~_mm_movemask_epi8(_mm_cmpeq_epi32(res, _mm_shuffle_epi32(res, 0)));
		u32 res32 = _mm_cvtsi128_si32(res);
		ok &= alleq == 0 && res32 == test.c;
		if (alleq != 0)
			printf("Not all vectors matched when testing %08x + %08x\n", test.a, test.b);
		else if (res32 == test.c)
			printf("%08x + %08x =[%s] %08x\n", test.a, test.b, name, res32);
		else
			printf("%08x + %08x =[%s] %08x != %08x\n", test.a, test.b, name, res32, test.c);
	}
	return ok;
}
#endif

int main(int argc, const char * argv[]) {
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
	bool ok = true;
	ok &= run_tests(ps2add, "CF");
	ok &= run_tests(ps2add_int, "CI");

#ifdef __x86_64__
	ok &= run_tests(ps2add_asm, "ASM");
	ok &= run_tests(ps2add_avx2, "AVX2");
	ok &= run_tests(ps2add_avx,  "AVX");
	ok &= run_tests(ps2add_sse4, "SSE4");
#endif
	if (ok)
		puts("All Pass");
	return ok ? 0 : 1;
}
