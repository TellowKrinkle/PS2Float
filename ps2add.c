#include <stdio.h>
#include <fenv.h>
#include <stdint.h>
#include <algorithm>

#pragma STDC FENV_ACCESS ON

typedef uint8_t u8;
typedef uint32_t u32;
typedef  int32_t s32;

#ifdef __x86_64__
#include <immintrin.h>
extern "C" u32 ps2add_asm(u32 a, u32 b);
extern "C" __m128i ps2add_avx2(__m128i a, __m128i b);
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

u32 ps2sub(u32 a, u32 b) {
	return ps2add(a, b ^ 0x80000000);
}

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
	printf("%08x\n", ps2sub(0x3f800000, 0x3cf776f9));
	printf("%08x\n", ps2add(0x7f7fffff, 0x7fffffff));
	printf("%08x\n", ps2sub(0x7ffddddd, 0x34480000));
	printf("%08x\n", ps2sub(0x7ffddddd, 0x7f800000));
	printf("%08x\n", ps2add(0xf4800000, 0x7ffddddd));
	printf("%08x\n", ps2add(0x7ffddddd, 0x7ffddddd));

#ifdef __x86_64__
	__m128i res = ps2add_avx2(
		_mm_setr_epi32(0x3f800000, 0x7ffddddd, 0xf4800000, 0x7ffddddd),
		_mm_setr_epi32(0xbcf776f9, 0xff800000, 0x7ffddddd, 0x7ffddddd));
	printf("\n");
	printf("%08x\n", _mm_extract_epi32(res, 0));
	printf("%08x\n", _mm_extract_epi32(res, 1));
	printf("%08x\n", _mm_extract_epi32(res, 2));
	printf("%08x\n", _mm_extract_epi32(res, 3));
#endif
	return 0;
}
