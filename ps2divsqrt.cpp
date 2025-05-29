#include "ps2float.h"

typedef uint32_t u32;
typedef  int32_t s32;

// Algorithm reference: DOI 10.1109/ARITH.1995.465363

struct CSAResult {
	u32 sum;
	u32 carry;
};

static CSAResult CSA(u32 a, u32 b, u32 c) {
	u32 lo = a ^ b ^ c;
	u32 hi = a + b + c - lo;
	return { lo, hi };
}

static int quotientSelect(CSAResult current) {
	// Note: Decimal point is between bits 24 and 25
	u32 mask = (1 << 24) - 1; // Bit 23 needs to be or'd in instead of added
	s32 test = ((current.sum & ~mask) + current.carry) | (current.sum & mask);
	if (test >= 1 << 23) { // test >= 0.25
		return 1;
	} else if (test < static_cast<s32>(~0u << 24)) { // test < -0.5
		return -1;
	} else {
		return 0;
	}
}

u32 ps2div(u32 a, u32 b) {
	u32 am = mantissa(a) << 2;
	u32 bm = mantissa(b) << 2;
	CSAResult current = { am, 0 };
	u32 quotient = 0;
	int quotientBit = 1;
	for (int i = 0; i < 25; i++) {
		quotient = (quotient << 1) + quotientBit;
		u32 add = quotientBit > 0 ? ~bm : quotientBit < 0 ? bm : 0;
		current.carry += quotientBit > 0;
		CSAResult csa = CSA(current.sum, current.carry, add);
		quotientBit = quotientSelect(quotientBit ? csa : current);
		current.sum   = csa.sum   << 1;
		current.carry = csa.carry << 1;
	}
	u32 sign = ((a ^ b) & 0x80000000);
	int cexp = exponent(a) - exponent(b) + 126;
	if (quotient >= (1 << 24)) {
		cexp += 1;
		quotient >>= 1;
	}
	if (exponent(b) == 0 || cexp > 255) {
		return sign | 0x7fffffff;
	} else if (exponent(a) == 0 || cexp < 1) {
		return sign;
	}
	return (quotient & 0x7fffff) | (cexp << 23) | sign;
}

u32 ps2sqrt(u32 val) {
	u32 m = mantissa(val) << 1;
	if (!(val & 0x800000)) // If exponent is odd after subtracting bias of 127
		m <<= 1;
	CSAResult current = { m, 0 };
	u32 quotient = 0;
	int quotientBit = 1;
	for (int i = 0; i < 25; i++) {
		// Adding n to quotient adds n * (2*quotient + n) to quotient^2
		// (which is what we need to subtract from the remainder)
		u32 adjust = quotient + (quotientBit << (24 - i));
		quotient += quotientBit << (25 - i);
		u32 add = quotientBit > 0 ? ~adjust : quotientBit < 0 ? adjust : 0;
		current.carry += quotientBit > 0;
		CSAResult csa = CSA(current.sum, current.carry, add);
		quotientBit = quotientSelect(quotientBit ? csa : current);
		current.sum   = csa.sum   << 1;
		current.carry = csa.carry << 1;
	}
	int exp = exponent(val);
	if (exp == 0)
		return 0;
	exp = (exp + 127) >> 1;
	return ((quotient >> 2) & 0x7fffff) | (exp << 23);
}
