#include "ps2float.h"
#include <algorithm>

#pragma STDC FENV_ACCESS ON

typedef uint8_t u8;
typedef uint16_t u16;
typedef uint32_t u32;
typedef  int32_t s32;

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
