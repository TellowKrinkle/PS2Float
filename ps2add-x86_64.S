#ifdef __x86_64__

.intel_syntax noprefix
.text
#ifdef __APPLE__
#define GNAME(x) _##x
#else
#define GNAME(x) x
#endif

.balign 16
.globl GNAME(ps2add_asm)
GNAME(ps2add_asm):
	mov    r8d, 0x7fffffff // r8d = 0x7fffffff
	mov    eax, edi
	mov    edx, esi
	and    eax, r8d        // eax = a & 0x7fffffff
	and    edx, r8d        // edx = b & 0x7fffffff
	mov    ecx, edi
	cmp    eax, edx        // if (eax < edx)
	cmovb  edi, esi        //   swap esi, edi
	cmovb  esi, ecx
	mov    eax, edi
	shr    eax, 23         // eax = a >> 23
	xor    edx, edx
	mov    ecx, (2 << 23)
	cmp    al, 254
	cmovae edx, ecx        // edx = eax >= 254 ? (2 << 23) : 0
	mov    ecx, esi
	shr    ecx, 23         // ecx = b >> 23
	sub    eax, ecx        // eax = (a >> 23) - (b >> 23)
	sub    edi, edx        // a -= adjust
	sub    esi, edx        // b -= adjust
	lea    ecx, [rax - 1]  // ecx = shift - 1
	mov    r9d, ~0
	shl    r9d, cl         // r9d = ~0u >> (shift - 1)
	and    r9d, esi        // r9d = b & (~0u >> (shift - 1))
	mov    ecx, esi
	and    ecx, 0x80000000 // ecx = b & 0x8000000
	cmp    al, 2           // if (shift >= 2)
	cmovae esi, r9d        //   b = r9d
	cmp    al, 25          // if (shift >= 25)
	cmovae esi, ecx        //   b = ecx
	movd   xmm0, edi
	movd   xmm1, esi
	addss  xmm0, xmm1
	movd   eax, xmm0       // rax = a * b
	or     r8d, eax        // r8d = rax | 0x7fffffff
	mov    ecx, eax        // ecx = eax
	add    eax, edx        // eax += adjust
	cmovo  eax, r8d        // if (overflow) eax = r8d
	test   ecx, ecx        // if (!ecx)
	cmovz  eax, ecx        //   eax = ecx
	ret

.balign 16
.globl GNAME(ps2add_avx2)
GNAME(ps2add_avx2):
	vbroadcastss xmm5, [rip + mask_rest]     // xmm5 = 0x7fffffff
	vpand        xmm2, xmm5, xmm0            // xmm2 = a & 0x7fffffff
	vpand        xmm3, xmm5, xmm1            // xmm3 = b & 0x7fffffff
	vpcmpgtd     xmm3, xmm3, xmm2            // xmm3 = (b & 0x7fffffff) > (a & 0x7fffffff)
	vpblendvb    xmm6, xmm0, xmm1, xmm3      // xmm6 = max(a, b)
	vpblendvb    xmm7, xmm1, xmm0, xmm3      // xmm7 = min(a, b)
	vbroadcastss xmm4, [rip + mask_exponent] // xmm4 = 0x7f800000
	vpand        xmm0, xmm6, xmm4            // xmm0 = exponent(xmm6)
	vpand        xmm1, xmm7, xmm4            // xmm1 = exponent(xmm7)
	vbroadcastss xmm4, [rip + const_exp_253] // xmm4 = 253 << 23
	vpcmpgtd     xmm3, xmm0, xmm4            // xmm3 = exponent(xmm6) > 253
	vbroadcastss xmm4, [rip + const_exp_2]   // xmm4 = 2 << 23
	vpand        xmm3, xmm3, xmm4            // xmm3 = adjust = exponent(xmm6) > 253 ? 2 << 23 : 0
	vpsubd       xmm0, xmm0, xmm1            // xmm0 = shift  = exponent(xmm6) - exponent(xmm7)
	vpsubd       xmm6, xmm6, xmm3            // xmm6 -= adjust
	vpsubd       xmm7, xmm7, xmm3            // xmm7 -= adjust
	vpcmpeqd     xmm1, xmm1, xmm1            // xmm1 = ~0u
	vbroadcastss xmm4, [rip + const_exp_1]   // xmm4 = 1 << 23
	vpcmpgtd     xmm2, xmm0, xmm4            // xmm2 = shift > 1
	vpsubd       xmm4, xmm0, xmm4            // xmm4 = shift - 1
	vpsrld       xmm4, xmm4, 23              // xmm4 >>= 23
	vpsllvd      xmm1, xmm1, xmm4            // xmm1 <<= (shift - 1)
	vpand        xmm1, xmm1, xmm7            // xmm1 = xmm7 & (~0u << (shift - 1))
	vbroadcastss xmm4, [rip + mask_sign]     // xmm4 = 0x80000000
	vpand        xmm4, xmm4, xmm7            // xmm4 = xmm7 & 0x80000000
	vpblendvb    xmm7, xmm7, xmm1, xmm2      // if (shift > 1) xmm7 &= (~0u << (shift - 1))
	vbroadcastss xmm1, [rip + const_exp_24]  // xmm1 = 24 << 23
	vpcmpgtd     xmm0, xmm0, xmm1            // xmm0 = shift > 24
	vpblendvb    xmm7, xmm7, xmm4, xmm0      // if (shift > 24) xmm7 = min(a, b) & 0x80000000
	vaddps       xmm0, xmm6, xmm7            // xmm0 = res = a + b
	vpxor        xmm4, xmm4, xmm4            // xmm4 = 0
	vpcmpeqd     xmm4, xmm4, xmm0            // xmm4 = res == 0
	vorps        xmm1, xmm5, xmm0            // xmm1 = res | 0x7fffffff
	vpaddd       xmm2, xmm0, xmm3            // xmm2 = res + adjust
	vpxor        xmm3, xmm0, xmm2            // xmm3 = res ^ (res + adjust)
	vblendvps    xmm0, xmm2, xmm1, xmm3      // xmm0 = (xmm3 & 0x80000000) ? xmm1 : xmm2
	vpandn       xmm0, xmm4, xmm0            // if (res == 0) xmm4 = 0
	ret

.balign 16
.globl GNAME(ps2add_avx)
GNAME(ps2add_avx):
	vbroadcastss xmm5, [rip + mask_rest]     // xmm5 = 0x7fffffff
	vpand        xmm2, xmm5, xmm0            // xmm2 = a & 0x7fffffff
	vpand        xmm3, xmm5, xmm1            // xmm3 = b & 0x7fffffff
	vpcmpgtd     xmm3, xmm3, xmm2            // xmm3 = (b & 0x7fffffff) > (a & 0x7fffffff)
	vpblendvb    xmm6, xmm0, xmm1, xmm3      // xmm6 = max(a, b)
	vpblendvb    xmm7, xmm1, xmm0, xmm3      // xmm7 = min(a, b)
	vbroadcastss xmm4, [rip + mask_exponent] // xmm4 = 0x7f800000
	vpand        xmm0, xmm6, xmm4            // xmm0 = exponent(xmm6)
	vpand        xmm1, xmm7, xmm4            // xmm1 = exponent(xmm7)
	vbroadcastss xmm4, [rip + const_exp_253] // xmm4 = 253 << 23
	vpcmpgtd     xmm3, xmm0, xmm4            // xmm3 = exponent(xmm6) > 253
	vbroadcastss xmm4, [rip + const_exp_2]   // xmm4 = 2 << 23
	vpand        xmm3, xmm3, xmm4            // xmm3 = adjust = exponent(xmm6) > 253 ? 2 << 23 : 0
	vpsubd       xmm0, xmm0, xmm1            // xmm0 = shift  = exponent(xmm6) - exponent(xmm7)
	vpsubd       xmm6, xmm6, xmm3            // xmm6 -= adjust
	vpsubd       xmm7, xmm7, xmm3            // xmm7 -= adjust
	vbroadcastss xmm4, [rip + const_fp_half] // xmm4 = 0.5f
	vpaddd       xmm4, xmm4, xmm0            // xmm4 = shift - 1 + exponent(1.0f)
	vcvttps2dq   xmm4, xmm4                  // AVX: "We have variable left shift at home"
	vpxor        xmm2, xmm2, xmm2            // xmm2 = 0
	vpsubd       xmm2, xmm2, xmm4            // xmm2 = -xmm4 (converts 1 << x to ~0u << x)
	vpand        xmm1, xmm2, xmm7            // xmm1 = xmm7 & (~0u << (shift - 1))
	vbroadcastss xmm4, [rip + const_exp_1]   // xmm4 = 1 << 23
	vpcmpgtd     xmm2, xmm0, xmm4            // xmm2 = shift > 1
	vbroadcastss xmm4, [rip + mask_sign]     // xmm4 = 0x80000000
	vpand        xmm4, xmm4, xmm7            // xmm4 = xmm7 & 0x80000000
	vpblendvb    xmm7, xmm7, xmm1, xmm2      // if (shift > 1) xmm7 &= (~0u << (shift - 1))
	vbroadcastss xmm1, [rip + const_exp_24]  // xmm1 = 24 << 23
	vpcmpgtd     xmm0, xmm0, xmm1            // xmm0 = shift > 24
	vpblendvb    xmm7, xmm7, xmm4, xmm0      // if (shift > 24) xmm7 = min(a, b) & 0x80000000
	vaddps       xmm0, xmm6, xmm7            // xmm0 = res = a + b
	vpxor        xmm4, xmm4, xmm4            // xmm4 = 0
	vpcmpeqd     xmm4, xmm4, xmm0            // xmm4 = res == 0
	vorps        xmm1, xmm5, xmm0            // xmm1 = res | 0x7fffffff
	vpaddd       xmm2, xmm0, xmm3            // xmm2 = res + adjust
	vpxor        xmm3, xmm0, xmm2            // xmm3 = res ^ (res + adjust)
	vblendvps    xmm0, xmm2, xmm1, xmm3      // xmm0 = (xmm3 & 0x80000000) ? xmm1 : xmm2
	vpandn       xmm0, xmm4, xmm0            // if (res == 0) xmm0 = 0
	ret

.balign 16
.globl GNAME(ps2add_sse4)
GNAME(ps2add_sse4):
	movdqa   xmm6, xmm0
	movdqa   xmm7, xmm1
	movdqa   xmm2, [rip + sse_mask_rest]
	pand     xmm2, xmm0                      // xmm2 = a & 0x7fffffff
	movdqa   xmm0, [rip + sse_mask_rest]
	pand     xmm0, xmm1                      // xmm0 = b & 0x7fffffff
	pcmpgtd  xmm0, xmm2                      // xmm0 = (b & 0x7fffffff) > (a & 0x7fffffff)
	pblendvb xmm7, xmm6, xmm0                // xmm7 = min(a, b)
	pblendvb xmm6, xmm1, xmm0                // xmm6 = max(a, b)
	movdqa   xmm0, [rip + sse_mask_exponent]
	movdqa   xmm1, [rip + sse_mask_exponent]
	pand     xmm0, xmm6                      // xmm0 = exponent(xmm6)
	pand     xmm1, xmm7                      // xmm1 = exponent(xmm7)
	movdqa   xmm3, xmm0
	pcmpgtd  xmm3, [rip + sse_const_exp_253] // xmm3 = exponent(xmm6) > 253
	pand     xmm3, [rip + sse_const_exp_2]   // xmm3 = adjust = exponent(xmm6) > 253 ? 2 << 23 : 0
	psubd    xmm0, xmm1                      // xmm0 = shift  = exponent(xmm6) - exponent(xmm7)
	psubd    xmm6, xmm3                      // xmm6 -= adjust
	psubd    xmm7, xmm3                      // xmm7 -= adjust
	movdqa   xmm5, xmm0
	movdqa   xmm2, [rip + sse_const_fp_half]
	paddd    xmm2, xmm0                      // xmm2 = shift - 1 + exponent(1.0f)
	cvttps2dq xmm2, xmm2                     // SSE: "We have variable left shift at home"
	pxor     xmm1, xmm1                      // xmm1 = 0
	psubd    xmm1, xmm2                      // xmm2 = -xmm2 (converts 1 << x to ~0u << x)
	pand     xmm1, xmm7                      // xmm1 = xmm7 & (~0u << (shift - 1))
	pcmpgtd  xmm0, [rip + sse_const_exp_1]   // xmm0 = shift > 1
	movdqa   xmm4, [rip + sse_mask_sign]
	pand     xmm4, xmm7                      // xmm4 = xmm7 & 0x80000000
	pblendvb xmm7, xmm1, xmm0                // if (shift > 1) xmm7 &= (~0u << (shift - 1))
	movdqa   xmm0, xmm5
	pcmpgtd  xmm0, [rip + sse_const_exp_24]  // xmm0 = shift > 24
	pblendvb xmm7, xmm4, xmm0                // if (shift > 24) xmm7 = min(a, b) & 0x80000000
	addps    xmm6, xmm7                      // xmm6 = res = a + b
	movdqa   xmm0, xmm6
	paddd    xmm3, xmm6                      // xmm3 = res + adjust
	movaps   xmm4, [rip + sse_mask_rest]
	orps     xmm4, xmm6                      // xmm4 = res | 0x7fffffff
	pxor     xmm0, xmm3                      // xmm0 = res ^ (res + adjust)
	blendvps xmm3, xmm4, xmm0                // xmm3 = (xmm0 ^ 0x80000000) ? xmm3 : xmm6
	pxor     xmm0, xmm0                      // xmm0 = 0
	pcmpeqd  xmm0, xmm6                      // xmm0 = res == 0
	pandn    xmm0, xmm3                      // xmm0 = res == 0 ? 0 : xmm3
	ret

.balign 16
.globl GNAME(ps2add_int_asm)
GNAME(ps2add_int_asm):
	mov    r11d, 0x7fffffff
	mov    eax, edi
	mov    edx, esi
	and    eax, r11d        // eax = a & 0x7fffffff
	and    edx, r11d        // edx = b & 0x7fffffff
	mov    ecx, edi
	cmp    eax, edx         // if (eax < edx)
	cmovb  edi, esi         //   swap esi, edi
	cmovb  esi, ecx
	mov    eax, 0x7fffff
	mov    edx, esi
	and    edx, eax
	or     edx, 0x800000
	shl    edx, 1           // edx = bmant = ((b & 0x7fffff) | 0x800000) << 1
	mov    ecx, edi
	shr    ecx, 23          // ecx = a >> 23
	mov    r8d, esi
	shr    r8d, 23          // r8d = b >> 23
	mov    r9d, ecx         // r9d = a >> 23
	sub    ecx, r8d         // cl = shift = (a >> 23) - (b >> 23)
	sar    edx, cl          // bmant >>= shift
	xor    r10d, r10d
	cmp    cl, 25
	cmovae edx, r10d        // if (shift > 24) bmant = 0
	mov    ecx, edi
	xor    ecx, esi
	sar    ecx, 31          // eax = negate = static_cast<s32>(a ^ b) >> 31
	xor    edx, ecx
	sub    edx, ecx         // if (negate) edx = -edx
	and    eax, edi
	or     eax, 0x800000
	shl    eax, 1           // eax = amant = ((a & 0x7fffff) | 0x800000) << 1
	add    eax, edx         // amant += bmant
	bsr    edx, eax
	mov    ecx, edx
	xor    ecx, 31          // ecx = clz(amant)
	shl    eax, cl          // amant <<= clz(amant)
	shr    eax, 8           // amant >>= 31 - 23
	and    eax, 0x7fffff    // eax = amant & 0x7fffff
	sub    edx, 24          // edx = 7 - clz(amant)
	movzx  ecx, r9b         // ecx = aexp = ((a >> 23) & 0xff)
	or     r11d, edi
	mov    r10d, edi        // r11d = a | 0x7fffffff
	and    r10d, 0x80000000 // r10d = a & 0x80000000
	or     eax, r10d        // eax = (a & 0x80000000) | (amant & 0x7fffff)
	cmp    ecx, 32
	cmovl  r11d, r10d       // r11d = aexp < 32 ? a & 0x80000000 : a | 0x7fffffff
	and    r10d, esi        // r10d = a & b & 0x80000000
	test   ecx, ecx
	cmovnz r10d, edi        // r10d = aexp ? a : a & b & 0x80000000
	add    ecx, edx         // ecx = cexp = aexp + (7 - clz(amant))
	xor    edx, edx
	xor    esi, 0x80000000  // esi = b ^ 0x80000000
	cmp    edi, esi
	cmove  r11d, edx        // if (a == (b ^ 0x80000000)) r11d = 0
	sete   dl               // dl = a == (b ^ 0x80000000)
	shl    ecx, 23
	or     eax, ecx         // eax = (a & 0x80000000) | (cexp << 23) | (amant & 0x7fffff)
	test   r8b, r8b
	cmovz  r11d, r10d       // if (!bexp) r11d = r9d
	setz   r9b              // d9b = !bexp
	or     dl, r9b          // dl = !bexp || a == (b ^ 0x80000000)
	cmp    ecx, 1 << 23
	setl   cl               // cl = cexp > 255 || cexp < 1
	or     dl, cl           // dl = any special case
	test   dl, dl
	cmovnz eax, r11d        // if (any special case) eax = r11d
	ret

.balign 16
.globl GNAME(ps2add_int_avx)
GNAME(ps2add_int_avx):
	vbroadcastss xmm9, [rip + mask_sign]     // xmm4 = 0x80000000
	vpxor        xmm2, xmm0, xmm1            // xmm2 = a ^ b
	vpandn       xmm5, xmm9, xmm0            // xmm5 = a & 0x7fffffff
	vpandn       xmm3, xmm9, xmm1            // xmm3 = b & 0x7fffffff
	vpand        xmm2, xmm9, xmm2            // xmm2 = (a ^ b) & 0x80000000
	vpcmpgtd     xmm3, xmm3, xmm5            // xmm3 = (b & 0x7fffffff) > (a & 0x7fffffff)
	vpblendvb    xmm6, xmm0, xmm1, xmm3      // xmm6 = max(a, b)
	vpblendvb    xmm7, xmm1, xmm0, xmm3      // xmm7 = min(a, b)
	vbroadcastss xmm4, [rip + mask_exponent] // xmm4 = 0x7f800000
	vpand        xmm5, xmm4, xmm6            // xmm5 = exponent(a)
	vpand        xmm8, xmm4, xmm7            // xmm8 = exponent(b)
	vpsubd       xmm0, xmm5, xmm8            // xmm0 = shift = exponent(a) - exponent(b)
	vbroadcastss xmm4, [rip + mask_mantissa] // xmm4 = 0x007fffff
	vpand        xmm3, xmm4, xmm7            // xmm3 = b & 0x7fffff
	vpor         xmm3, xmm3, xmm2            // xmm3 = (b & 0x7fffff) | ((a ^ b) & 0x80000000)
	vpand        xmm2, xmm4, xmm6            // xmm2 = a & 0x7fffff
	vbroadcastss xmm1, [rip + const_exp_151] // xmm1 = (24 + 127) << 23
	vpsubd       xmm4, xmm1, xmm0            // xmm4 = ((25 - shift) + 127) << 23
	vpor         xmm3, xmm3, xmm4            // xmm3 = float{sign: sign(a) != sign(b), exp: 25 - shift, mantissa: mantissa(b)}
	vcvttps2dq   xmm3, xmm3                  // xmm3 = bmant
	vbroadcastss xmm4, [rip + const_exp_24]  // xmm4 = 24 << 23
	vpcmpgtd     xmm4, xmm0, xmm4            // xmm4 = shift > 24
	vpandn       xmm3, xmm4, xmm3            // xmm3 = shift > 24 ? 0 : bmant
	vbroadcastss xmm4, [rip + const_exp_1]   // xmm4 = 0x800000
	vpor         xmm2, xmm4, xmm2            // xmm2 = ((a & 0x7fffff) | 0x800000)
	vpslld       xmm2, xmm2, 1               // xmm2 = amant
	vpaddd       xmm2, xmm2, xmm3            // xmm2 = amant + bmant
	vpsrld       xmm3, xmm2, 24              // xmm3 = xmm2 >> 24
	vpandn       xmm3, xmm3, xmm2            // xmm3 = ensure cvtdq2ps rounds down (amant + bmant)
	vcvtdq2ps    xmm3, xmm3                  // xmm3 = float(amant + bmant)
	vpsubd       xmm2, xmm5, xmm1            // xmm2 = exponent(a) - 25
	vpaddd       xmm3, xmm3, xmm2            // xmm3 = special case ? -something : c & 0x7fffffff
	vpcmpgtd     xmm1, xmm5, xmm1            // xmm1 = exponent(a) > 151
	vpandn       xmm1, xmm9, xmm1            // xmm1 = exponent(a) > 151 ? 0x7fffffff : 0
	vpand        xmm0, xmm9, xmm6            // xmm0 = a & 0x80000000
	vpor         xmm1, xmm1, xmm0            // xmm1 = exponent(a) > 151 ? a | 0x7fffffff : a & 0x80000000
	vpxor        xmm2, xmm9, xmm7            // xmm2 = b ^ 0x80000000
	vpcmpeqd     xmm2, xmm2, xmm6            // xmm2 = a == (b ^ 0x80000000)
	vpandn       xmm1, xmm2, xmm1            // xmm1 = a == (b ^ 0x80000000) ? 0 : xmm1
	vpand        xmm7, xmm9, xmm7            // xmm7 = b & 0x80000000
	vpcmpgtd     xmm9, xmm4, xmm3            // xmm9 = (1 << 23) > xmm3
	vpxor        xmm4, xmm4, xmm4            // xmm4 = 0
	vpcmpgtd     xmm5, xmm5, xmm4            // xmm5 = exponent(a) > 0
	vpor         xmm5, xmm5, xmm7            // xmm5 = exponent(a) > 0 ? 0xffffffff : b & 0x80000000
	vpand        xmm5, xmm5, xmm6            // xmm5 = exponent(a) > 0 ? a : a & b & 0x80000000
	vpcmpeqd     xmm4, xmm8, xmm4            // xmm4 = exponent(b) == 0
	vpblendvb    xmm1, xmm1, xmm5, xmm4      // xmm1 = value if special case
	vpor         xmm4, xmm4, xmm2            // xmm4 = exponent(b) == 0 || a == (b ^ 0x80000000)
	vpor         xmm4, xmm9, xmm4            // xmm4 = special case ? -something : +something
	vpor         xmm3, xmm3, xmm0            // xmm3 = special case ? xxx : c
	vpblendvb    xmm0, xmm3, xmm1, xmm4      // xmm0 = c
	ret

.data
.balign 64
sse_mask_sign:
.int 0x80000000, 0x80000000, 0x80000000, 0x80000000
sse_mask_rest:
.int 0x7fffffff, 0x7fffffff, 0x7fffffff, 0x7fffffff
sse_mask_exponent:
.int 0x7f800000, 0x7f800000, 0x7f800000, 0x7f800000
sse_const_fp_half:
.int 0x3f000000, 0x3f000000, 0x3f000000, 0x3f000000
sse_const_exp_1:
.int   1 << 23,   1 << 23,   1 << 23,   1 << 23
sse_const_exp_2:
.int   2 << 23,   2 << 23,   2 << 23,   2 << 23
sse_const_exp_24:
.int  24 << 23,  24 << 23,  24 << 23,  24 << 23
sse_const_exp_253:
.int 253 << 23, 253 << 23, 253 << 23, 253 << 23

.balign 32
mask_sign:
.int 0x80000000
mask_rest:
.int 0x7fffffff
mask_exponent:
.int 0x7f800000
const_fp_half:
.int 0x3f000000
const_exp_1:
.int 1 << 23
const_exp_2:
.int 2 << 23
const_exp_24:
.int 24 << 23
const_exp_253:
.int 253 << 23
const_exp_151:
.int 151 << 23
mask_mantissa:
.int 0x007fffff

#endif // __x86_64__
