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
	u32 lo = a ^ b ^ c;
	u32 hi = a + b + c - lo;
	return { lo, hi };
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

template <u64(mulmantissa)(u32, u32)>
static u32 ps2mul_generic(u32 a, u32 b) {
	u32 ma = mantissa(a);
	u32 mb = mantissa(b);
	int ea = exponent(a);
	int eb = exponent(b);
	u32 sign = (a ^ b) & 0x80000000;
	if (!ea || !eb)
		return sign;
	int ec = ea + eb - 127;
	u32 mc = static_cast<u32>(mulmantissa(ma, mb) >> 23);
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

u32 ps2mul(u32 a, u32 b) {
	return ps2mul_generic<ps2mulmantissa>(a, b);
}

// SIMD-within-a-register PS2mul implementation

static u64 SpreadShiftedBits(u64 a) {
	// Get (a << (2*bit)) for each booth recode (0 to 7).
	//
	// One multiply is adequate to get the results of all 8 shifts into 8
	// bytes, but the resulting order is interleaved.
	//
	// SpreadBoothSelectors must match this order, and it is confusing,
	// but it doesn't otherwise complicate the rest of the code.
	//
	// The resulting order is given by:
	//
	//   b0: (values >> 8)  & 0xFF
	//   b1: (values >> 24) & 0xFF
	//   b2: (values >> 40) & 0xFF
	//   b3: (values >> 56) & 0xFF
	//   b4: (values >> 0)  & 0xFF
	//   b5: (values >> 16) & 0xFF
	//   b6: (values >> 32) & 0xFF
	//   b7: (values >> 48) & 0xFF
	//
	// Some junk is left in the low bits of b7, but we discard those later.

	a &= 0x7FFF;

	u64 values = a * 0x0040001000040001u;

	// We start with 6 bits per field, then narrow to 5 after booth doubling.
	return values & 0x7e7e7e7e7e7e7e7e;
}

static u64 SpreadBoothSelectors(u64 b) {
	// matches the interleaved order given by SpreadShiftedBits
	b &= 0xFFFF;
	u64 even = ((b >> 7) * 0x40010004001) & 0x0007000700070007;
	u64 odd  = (((b & 0xFF) << 9) * 0x40010004001) & 0x0700070007000700;
	return odd | even;
}

struct BoothRecode8x8 {
	u64 values;
	u64 negate_mask;
};

static BoothRecode8x8 BoothRecodeSWAR(u32 ma, u32 mb) {
	// SWAR constants
	const u64 low_bits = 0x0101010101010101;
	const u64 high_bits = low_bits * 0x80;

	// Booth Recode
	u64 selectors = SpreadBoothSelectors(mb);
	u64 values = SpreadShiftedBits(ma);

	// masks are 0x80 for false or 0x7f for true, but we don't care about the high bit

	// booth should negate
	u64 negate = ((selectors + (4 * low_bits)) & ~(selectors + (1 * low_bits))) >> 3;
	u64 negate_mask = (high_bits - (negate & low_bits));

	// booth should double
	u64 dbl = ((selectors + (5 * low_bits)) & ~(selectors + (3 * low_bits))) >> 3;
	u64 dbl_mask = (high_bits - (dbl & low_bits));

	// booth shouldn't zero
	u64 nonzero = ((selectors + (7 * low_bits)) & ~(selectors + (1 * low_bits))) >> 3;
	u64 nonzero_mask = (high_bits - (nonzero & low_bits));

	// booth recode
	values += values & dbl_mask;
	values ^= negate_mask;
	values &= nonzero_mask;

	return { values, negate_mask };
}

static u64 ps2mulmantissa_swar(u32 ma, u32 mb) {
	u64 full = static_cast<u64>(ma) * static_cast<u64>(mb);

	BoothRecode8x8 recoded = BoothRecodeSWAR(ma, mb);
	u64 values = recoded.values;
	u64 negate_mask = recoded.negate_mask;

	// Clear bits:
	// * At most we need 5 bits (0x7C).
	// * b7 and b6 have fewer bits (zeroes shifted in).
	// * b7 has junk bits from the multiply that must be cleared.
	// * b5 and b4 have bits that are ignored in the first cycle, so we mask
	//   them off but save them in unmasked_values for later.
	//
	//   b0 &= 0x7c
	//   b1 &= 0x7c
	//   b2 &= 0x7c
	//   b3 &= 0x7c
	//   b4 &= 0x78
	//   b5 &= 0x70
	//   b6 &= 0x70
	//   b7 &= 0x40
	u64 unmasked_values = values;
	values &= 0x7c407c707c707c78;


	// First cycle

	// t0 @ bit 24  = Add3(b1, b2, b3)
	// t1 @ bit 0   = Add3(b4, b5, b6)
	AddResult t01 = Add3(static_cast<u32>(values), static_cast<u32>(values >> 16), values >> 32);


	// A few adds get skipped, squeeze them back in

	// t1.hi += b6.negate;
	t01.hi += (negate_mask >> 32) & 0x10;
	// t1.hi += (b5.data & 0x800);
	t01.hi += (unmasked_values >> 16) & 8;

	// b7.data += (b5.data & 0x400) + b5.negate;
	values += ((unmasked_values & negate_mask) & 0x40000) << 33;


	// Second Cycle

	// move b0 from 8 to 24 (t0)
	// move b7 from 48 to 0 (t1)
	// (coincidentally a rotate)
	u64 second_pass = (values << 16) | (values >> 48);

	// Note: From this point many u64 ops could be replaced with u32 ops.

	// t2 @ 24  = Add3(b0, t0.lo, t0.hi)
	// t3 @ 0   = Add3(b7, t1.lo, t1.hi)
	AddResult t23 = Add3(static_cast<u32>(second_pass), t01.lo, t01.hi);

	// Third Cycle
	// t4 @ 0   = Add3(t2.hi, t3.lo, t3.hi)
	AddResult t4 = Add3(t23.hi >> 24, t23.lo, t23.hi);

	// Fourth Cycle
	// t5 @ 0   = Add3(t2.lo, t4.lo, t4.hi)
	AddResult t5 = Add3(t23.lo >> 24, t4.lo, t4.hi);

	// t5.hi += b7.negate;
	t5.hi += (negate_mask >> 48) & 0x40;

	// Calculate error
	u64 sub = ((t5.lo & 0x40) + (t5.hi & 0x40)) << 8;

	return full - sub;
}

u32 ps2mul_swar(u32 a, u32 b) {
	return ps2mul_generic<ps2mulmantissa_swar>(a, b);
}
