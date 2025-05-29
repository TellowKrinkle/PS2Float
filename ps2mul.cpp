#include "ps2float.h"

typedef uint32_t u32;
typedef uint64_t u64;

struct BoothRecode {
	u32 data;
	u32 negate;
};

struct AddResult {
	u32 lo;
	u32 hi;
};

static BoothRecode booth(u32 a, u32 b, u32 bit) {
	u32 test = (bit ? b >> (bit * 2 - 1) : b << 1) & 7;
	a <<= (bit * 2);
	a += (test == 3 || test == 4) ? a : 0;
	u32 neg = (test >= 4 && test <= 6) ? ~0u : 0;
	u32 pos = 1 << (bit * 2);
	a ^= (neg & -pos);
	a &= (test >= 1 && test <= 6) ? ~0u : 0;
	return { a, neg & pos };
}

// Add 3 rows of bits in parallel
static AddResult Add3(u32 a, u32 b, u32 c) {
	u32 u = a ^ b;
	u32 lo = u ^ c;
	u32 hi = (u & c) | (a & b);
	return { lo, hi << 1 };
}

static u64 ps2mulmantissa(u32 a, u32 b) {
	u64 full = static_cast<u64>(a) * static_cast<u64>(b);
	BoothRecode b0 = booth(a, b, 0);
	BoothRecode b1 = booth(a, b, 1);
	BoothRecode b2 = booth(a, b, 2);
	BoothRecode b3 = booth(a, b, 3);
	BoothRecode b4 = booth(a, b, 4);
	BoothRecode b5 = booth(a, b, 5);
	BoothRecode b6 = booth(a, b, 6);
	BoothRecode b7 = booth(a, b, 7);

	// First cycle
	AddResult t0 = Add3(b1.data, b2.data, b3.data);
	AddResult t1 = Add3(b4.data & ~0x7ffu, b5.data & ~0xfffu, b6.data);
	// A few adds get skipped, squeeze them back in
	t1.hi |= b6.negate | (b5.data & 0x800);
	b7.data |= (b5.data & 0x400) + b5.negate;

	// Second cycle
	AddResult t2 = Add3(b0.data, t0.lo, t0.hi);
	AddResult t3 = Add3(b7.data, t1.lo, t1.hi);

	// Third cycle
	AddResult t4 = Add3(t2.hi, t3.lo, t3.hi);

	// Fourth cycle
	AddResult t5 = Add3(t2.lo, t4.lo, t4.hi);

	// Discard bits and sum
	t5.hi += b7.negate;
	t5.lo &= ~0x7fffu;
	t5.hi &= ~0x7fffu;
	u32 ps2lo = t5.lo + t5.hi;
	return full - ((ps2lo ^ full) & 0x8000);
}

u32 ps2mul(u32 a, u32 b) {
	u32 ma = mantissa(a);
	u32 mb = mantissa(b);
	int ea = exponent(a);
	int eb = exponent(b);
	u32 sign = (a ^ b) & 0x80000000;
	if (!ea || !eb)
		return sign;
	int ec = ea + eb - 127;
	u32 mc = static_cast<u32>(ps2mulmantissa(ma, mb) >> 23);
	if (mc > 0xffffff) {
		mc >>= 1;
		ec++;
	}
	if (ec > 0xff)
		return sign | 0x7fffffff;
	if (ec <= 0)
		return sign;
	return sign | (ec << 23) | (mc & 0x7fffff);
}
