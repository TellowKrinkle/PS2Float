#ifdef __x86_64__

.intel_syntax noprefix
.text
#ifdef __APPLE__
#define GNAME(x) _##x
#else
#define GNAME(x) x
#endif

// Booth recode (with nonzero bit)
// If destructive, a == data and b == t0
.macro BOOTH a, b, bit, data, negate, t0, t0r, t1, ar=unused, calc_neg=0, mask_neg=0, destructive=0
.if \destructive
	shl    \data, (\bit * 2)
.else
.if \bit == 1
	lea    \data, [\ar * 4]
.else
	mov    \data, \a
	shl    \data, (\bit * 2)
.endif
	mov    \t0, \b
.endif
	and    \t0, (7 << (\bit * 2 - 1))
	xor    \negate, \negate
	lea    \t1, [\t0r - (3 << (\bit * 2 - 1))]
	cmp    \t1, (2 << (\bit * 2 - 1))
	cmovb  \negate, \data
	add    \data, \negate

.if \calc_neg
	lea    \negate, [\t0r - (4 << (\bit * 2 - 1))]
	cmp    \negate, (3 << (\bit * 2 - 1))
	sbb    \negate, \negate
.else
	xor    \negate, \negate
	cmp    \t0, (4 << (\bit * 2 - 1))
	adc    \negate, -1
.endif

.if \mask_neg
	and    \negate, -(1 << (\bit * 2))
	xor    \data, \negate
.if \calc_neg
	neg    \negate
.endif
.else
	xor    \data, \negate
.if \calc_neg
	and    \negate, 1 << (\bit * 2)
.endif
.endif

	xor    \t1, \t1
	sub    \t0, (1 << (\bit * 2 - 1))
	cmp    \t0, (6 << (\bit * 2 - 1))
	cmovae \data, \t1
.endm

.macro CSA a, b, c, tmp, link=0
	mov \tmp, \a
	xor \a, \b
	xor \a, \c
	add \b, \tmp
	add \b, \c
.if \link == 0
	sub \b, \a
.endif
.endm

// CSA where l and h are the low and high outputs from a previous CSA with link=1
.macro CSA_LINK l, b, h, tmp, link=0
	mov \tmp, \h
	sub \h, \l
	xor \l, \b
	xor \l, \h
	add \b, \tmp
.if \link == 0
	sub \b, \l
.endif
.endm

.macro CSA_AVX a, b, c, tmp, addop=vpaddw, subop=vpsubw, link=0
	vpxor  \tmp, \a, \b
	\addop \b, \a, \b
	vpxor  \a, \c, \tmp
	\addop \b, \c, \b
.if \link == 0
	\subop \b, \b, \a
.endif
.endm

// CSA where lh is a precalculated l + h
.macro CSA_AVX_LINK l, lh, c, h, addop=vpaddw, subop=vpsubw, link=0
	vpxor  \l, \c, \l
	vpxor  \l, \h, \l
	\addop \lh, \c, \lh
.if \link == 0
	\subop \lh, \lh, \l
.endif
.endm

// CSA that preserves its inputs
.macro CSA_AVX_ND o0, o1, a, b, c, addop=vpaddw, subop=vpsubw, link=0
	vpxor  \o0, \a, \b
	vpxor  \o0, \c, \o0
	\addop \o1, \a, \b
	\addop \o1, \c, \o1
.if \link == 0
	\subop \o1, \o1, \o0
.endif
.endm

.macro CSA_SSE a, b, c, tmp, addop=paddw, subop=psubw, link=0
	movdqa \tmp, \a
	pxor   \a, \b
	pxor   \a, \c
	\addop \b, \tmp
	\addop \b, \c
.if \link == 0
	\subop \b, \a
.endif
.endm

.macro CSA_SSE_LINK l, lh, c, h, addop=paddw, subop=psubw, link=0
	pxor   \l, \c
	pxor   \l, \h
	\addop \lh, \c
.if \link == 0
	\subop \lh, \l
.endif
.endm

.balign 16
.globl GNAME(ps2mul_asm)
GNAME(ps2mul_asm):
	push   rbx
	push   r12

	mov    r8d, edi
	mov    r9d, esi

	BOOTH a=edi, b=esi, bit=4, data=eax, negate=ecx, t0=ebx, t0r=rbx, t1=edx
	BOOTH a=edi, b=esi, bit=5, data=edx, negate=ecx, t0=ebx, t0r=rbx, t1=r10d, calc_neg=1
	BOOTH a=edi, b=esi, bit=6, data=edi, negate=ebx, t0=esi, t0r=rsi, t1=r10d, calc_neg=1, mask_neg=1, destructive=1
	mov    r10d, edx
	and    r10d, 0x400
	add    r10d, ecx         // r10d = (b5.data & 0x400) + b5.negate
	mov    ecx, edx
	and    ecx, 0x800
	or     ebx, ecx          // ebx = b6.negate | (b5.data & 0x800)
	and    edx, ~0xfff
	CSA a=eax, b=edx, c=edi, tmp=ecx, link=1
	// edx currently holds t1.hi + t1.lo (subtraction pending), so we add instead of or, since it will work regardless.
	add    edx, ebx          // t1.hi += b6.negate | (b5.data & 0x800)

	BOOTH a=r8d, b=r9d, bit=1, data=ebx, negate=edi, t0=esi,  t0r=rsi, t1=ecx, ar=r8
	BOOTH a=r8d, b=r9d, bit=2, data=ecx, negate=edi, t0=esi,  t0r=rsi, t1=r12d
	BOOTH a=r8d, b=r9d, bit=3, data=edi, negate=esi, t0=r11d, t0r=r11, t1=r12d
	CSA a=ebx, b=ecx, c=edi, tmp=esi, link=1

	BOOTH a=r8d, b=r9d, bit=7, data=edi, negate=r11d, t0=esi, t0r=rsi, t1=r12d, calc_neg=1, mask_neg=1
	or     edi, r10d         // b7.data |= (b5.data & 0x400) + b5.negate
	CSA_LINK l=eax, b=edi, h=edx, tmp=esi, link=1

	// Manual bit=0 booth for b0
	mov    edx, r8d
	mov    r10d, r9d
	and    r10d, 3
	xor    esi, esi
	cmp    r10d, 2
	cmove  esi, edx
	add    edx, esi
	xor    esi, esi
	cmp    r10d, 2
	adc    esi, -1
	xor    edx, esi
	xor    esi, esi
	test   r10d, r10d
	cmovz  edx, esi
	CSA_LINK l=ebx, b=edx, h=ecx, tmp=esi

	CSA_LINK l=eax, b=edx, h=edi, tmp=esi, link=1
	CSA_LINK l=eax, b=ebx, h=edx, tmp=esi

	add    ebx, r11d        // t5.hi += b7.negate
	xor    eax, ebx         // ps2lo = t5.lo ^ t5.hi

	mov    ecx, r8d
	mov    edx, r9d
	and    ecx, 0x7fffff
	and    edx, 0x7fffff
	or     ecx, 0x800000
	or     edx, 0x800000
	imul   rcx, rdx         // rcx = full

	and    eax, 0x8000
	sub    rcx, rax
	shr    rcx, 23          // rcx = mc

	mov    eax, r8d
	mov    edx, r9d
	xor    r8d, r9d
	and    r8d, 0x80000000  // r8d = sign = (a ^ b) & 0x80000000
	and    eax, 0x7f800000
	jz     Lps2mul_asm_mul_zero
	and    edx, 0x7f800000
	jz     Lps2mul_asm_mul_zero

	add    eax, edx
	sub    eax, (127 << 23) // eax = exponent(a) + exponent(b) - 127

	mov    edx, ecx
	shr    ecx, 1
	mov    edi, ecx
	and    ecx, 0x800000
	cmovz  edi, edx
	add    eax, ecx
	and    edi, 0x7fffff

	cmp    eax, (1 << 23)
	jl     Lps2mul_asm_out_of_range

	or     eax, r8d
	or     eax, edi

Lps2mul_asm_done:
	pop    r12
	pop    rbx
	ret

Lps2mul_asm_mul_zero:
	mov    eax, r8d         // return sign
	jmp    Lps2mul_asm_done

Lps2mul_asm_out_of_range:
	mov    edx, r8d
	or     edx, 0x7fffffff  // edx = sign | 0x7fffffff
	cmp    eax, (-127 << 23)
	mov    eax, r8d
	cmovl  eax, edx         // return overflow ? sign | 0x7fffffff : sign
	jmp    Lps2mul_asm_done

.balign 16
.globl GNAME(ps2mul_one_avx2)
GNAME(ps2mul_one_avx2):
	vpshufb      xmm3, xmm1, [rip + one_b_shuf]
	vpmullw      xmm3, xmm3, [rip + one_b_shift] // xmm3 = b << (bit * 2 + 7)
	vpbroadcastw xmm2, xmm0
	vmovdqa      xmm5, [rip + one_pos]
	vpmullw      xmm2, xmm2, xmm5                // xmm2 = a << (bit * 2)
	vpbroadcastd xmm4, [rip + const_7b]
	vpand        xmm3, xmm3, xmm4                // xmm3 = test = (b << (bit * 2 - 1)) & 7
	vmovq        xmm4, [rip + booth_table]
	vpshufb      xmm4, xmm4, xmm3                // xmm4 = booth[test] << 8
	vpsraw       xmm3, xmm4, 8                   // xmm3 = booth[test]
	vpmullw      xmm2, xmm2, xmm3                // xmm2 = a * booth[test]
	vpsraw       xmm4, xmm4, 15                  // xmm4 = booth[test] < 0 ? ~0 : 0
	vpand        xmm4, xmm4, xmm5                // xmm4 = negate[test]
	vpsubw       xmm2, xmm2, xmm4                // xmm2 = booth(a) (correct negate to invert)
	vmovd        eax, xmm0
	vmovd        edx, xmm1
	vmovd        xmm1, [rip + mask_fff]
	vpandn       xmm1, xmm1, xmm2                // xmm1 = b5.data & ~0xfffu, b2.data
	vpsrlq       xmm0, xmm2, 32                  // xmm0 = b4.data,           b1.data
	vpunpckhqdq  xmm3, xmm2, xmm2                // xmm3 = b6.data,           b3.data
	CSA_AVX a=xmm0, b=xmm1, c=xmm3, tmp=xmm5, link=1
	vpbroadcastd xmm5, [rip + mask_ffff]
	vpand        xmm4, xmm4, xmm5                // mask out negate of b0-b3
	vpunpckhqdq  xmm3, xmm4, xmm4                // xmm4 = b6.negate
	vmovd        xmm5, [rip + mask_800]
	vpand        xmm5, xmm5, xmm2                // xmm5 = b5.data & 0x800
	vpor         xmm3, xmm3, xmm5                // xmm3 = b6.negate | (b5.data & 0x800)
	vpaddw       xmm1, xmm1, xmm3                // t1.hi += b6.negate | (b5.data & 0x800)
	vpshufd      xmm3, xmm2, 3                   // xmm3 = b7.data, b0.data
	vmovd        xmm5, [rip + mask_400]
	vpand        xmm5, xmm5, xmm2                // xmm5 = b5.data & 0x400
	vpaddw       xmm5, xmm5, xmm4                // xmm5 = (b5.data & 0x400) + b5.negate, 0, xxx...
	vpor         xmm3, xmm3, xmm5                // b7.data |= (b5.data & 0x400) + b5.negate
	vpsubw       xmm5, xmm1, xmm0                // Finish CSA for t0 and t1
	CSA_AVX_LINK l=xmm0, lh=xmm1, c=xmm3, h=xmm5, link=1
	vpsubw       xmm5, xmm1, xmm0                // Finish CSA for t2 and t3
	vpsrld       xmm2, xmm0, 16                  // xmm2 = t2.lo
	vpsrld       xmm3, xmm5, 16                  // xmm3 = t2.hi
	CSA_AVX_LINK l=xmm0, lh=xmm1, c=xmm3, h=xmm5, link=1
	vpsubw       xmm5, xmm1, xmm0                // Finish CSA for t4
	CSA_AVX_LINK l=xmm0, lh=xmm1, c=xmm2, h=xmm5
	vpshufd      xmm4, xmm4, 3
	vpaddd       xmm1, xmm1, xmm4                // t5.hi += b7.negate
	vpxor        xmm0, xmm0, xmm1                // xmm0 = ps2lo = t5.lo ^ t5.hi

	mov          esi, eax
	mov          edi, edx
	and          esi, 0x7fffff
	and          edi, 0x7fffff
	or           esi, 0x800000
	or           edi, 0x800000
	imul         rsi, rdi                        // rsi = full

	vmovd        edi, xmm0
	and          edi, 0x8000
	sub          rsi, rdi
	shr          rsi, 23                         // rsi = mc

	mov          ecx, eax
	xor          ecx, edx
	and          ecx, 0x80000000                 // ecx = sign = (a ^ b) & 0x80000000
	and          eax, 0x7f800000                 // eax = exponent(a)
	jz           Lps2mul_avx2_mul_zero
	and          edx, 0x7f800000                 // edx = exponent(b)
	jz           Lps2mul_avx2_mul_zero

	add          eax, edx
	sub          eax, (127 << 23)                // eax = exponent(a) + exponent(b) - 127

	mov          edx, esi
	shr          esi, 1
	mov          edi, esi
	and          esi, 0x800000
	cmovz        edi, edx
	add          eax, esi
	and          edi, 0x7fffff

	cmp          eax, (1 << 23)
	jl           Lps2mul_avx2_out_of_range

	or           eax, ecx
	or           eax, edi

Lps2mul_avx2_done:
	vmovd        xmm0, eax
	vpbroadcastd xmm0, xmm0                      // Not really necessary, but tests want the result in all lanes to verify multilane vector functions
	ret

Lps2mul_avx2_mul_zero:
	mov          eax, ecx                        // return sign
	jmp          Lps2mul_avx2_done

Lps2mul_avx2_out_of_range:
	mov          edx, ecx
	or           edx, 0x7fffffff                 // edx = sign | 0x7fffffff
	cmp          eax, (-127 << 23)
	mov          eax, ecx
	cmovl        eax, edx                        // return overflow ? sign | 0x7fffffff : sign
	jmp          Lps2mul_avx2_done

.balign 16
.globl GNAME(ps2mul_one_avx)
GNAME(ps2mul_one_avx):
	vpshufb      xmm3, xmm1, [rip + one_b_shuf]
	vpmullw      xmm3, xmm3, [rip + one_b_shift] // xmm3 = b << (bit * 2 + 7)
	vbroadcastss xmm4, [rip + one_b_shuf + 4]
	vpshufb      xmm2, xmm0, xmm4
	vmovdqa      xmm5, [rip + one_pos]
	vpmullw      xmm2, xmm2, xmm5                // xmm2 = a << (bit * 2)
	vbroadcastss xmm4, [rip + const_7b]
	vpand        xmm3, xmm3, xmm4                // xmm3 = test = (b << (bit * 2 - 1)) & 7
	vmovq        xmm4, [rip + booth_table]
	vpshufb      xmm4, xmm4, xmm3                // xmm4 = booth[test] << 8
	vpsraw       xmm3, xmm4, 8                   // xmm3 = booth[test]
	vpmullw      xmm2, xmm2, xmm3                // xmm2 = a * booth[test]
	vpsraw       xmm4, xmm4, 15                  // xmm4 = booth[test] < 0 ? ~0 : 0
	vpand        xmm4, xmm4, xmm5                // xmm4 = negate[test]
	vpsubw       xmm2, xmm2, xmm4                // xmm2 = booth(a) (correct negate to invert)
	vmovd        eax, xmm0
	vmovd        edx, xmm1
	vmovd        xmm1, [rip + mask_fff]
	vpandn       xmm1, xmm1, xmm2                // xmm1 = b5.data & ~0xfffu, b2.data
	vpsrlq       xmm0, xmm2, 32                  // xmm0 = b4.data,           b1.data
	vpunpckhqdq  xmm3, xmm2, xmm2                // xmm3 = b6.data,           b3.data
	CSA_AVX a=xmm0, b=xmm1, c=xmm3, tmp=xmm5, link=1
	vbroadcastss xmm5, [rip + mask_ffff]
	vpand        xmm4, xmm4, xmm5                // mask out negate of b0-b3
	vpunpckhqdq  xmm3, xmm4, xmm4                // xmm4 = b6.negate
	vmovd        xmm5, [rip + mask_800]
	vpand        xmm5, xmm5, xmm2                // xmm5 = b5.data & 0x800
	vpor         xmm3, xmm3, xmm5                // xmm3 = b6.negate | (b5.data & 0x800)
	vpaddw       xmm1, xmm1, xmm3                // t1.hi += b6.negate | (b5.data & 0x800)
	vpshufd      xmm3, xmm2, 3                   // xmm3 = b7.data, b0.data
	vmovd        xmm5, [rip + mask_400]
	vpand        xmm5, xmm5, xmm2                // xmm5 = b5.data & 0x400
	vpaddw       xmm5, xmm5, xmm4                // xmm5 = (b5.data & 0x400) + b5.negate, 0, xxx...
	vpor         xmm3, xmm3, xmm5                // b7.data |= (b5.data & 0x400) + b5.negate
	vpsubw       xmm5, xmm1, xmm0                // Finish CSA for t0 and t1
	CSA_AVX_LINK l=xmm0, lh=xmm1, c=xmm3, h=xmm5, link=1
	vpsubw       xmm5, xmm1, xmm0                // Finish CSA for t2 and t3
	vpsrld       xmm2, xmm0, 16                  // xmm2 = t2.lo
	vpsrld       xmm3, xmm5, 16                  // xmm3 = t2.hi
	CSA_AVX_LINK l=xmm0, lh=xmm1, c=xmm3, h=xmm5, link=1
	vpsubw       xmm5, xmm1, xmm0                // Finish CSA for t4
	CSA_AVX_LINK l=xmm0, lh=xmm1, c=xmm2, h=xmm5
	vpshufd      xmm4, xmm4, 3
	vpaddd       xmm1, xmm1, xmm4                // t5.hi += b7.negate
	vpxor        xmm0, xmm0, xmm1                // xmm0 = ps2lo = t5.lo ^ t5.hi

	mov          esi, eax
	mov          edi, edx
	and          esi, 0x7fffff
	and          edi, 0x7fffff
	or           esi, 0x800000
	or           edi, 0x800000
	imul         rsi, rdi                        // rsi = full

	vmovd        edi, xmm0
	and          edi, 0x8000
	sub          rsi, rdi
	shr          rsi, 23                         // rsi = mc

	mov          ecx, eax
	xor          ecx, edx
	and          ecx, 0x80000000                 // ecx = sign = (a ^ b) & 0x80000000
	and          eax, 0x7f800000                 // eax = exponent(a)
	jz           Lps2mul_avx_mul_zero
	and          edx, 0x7f800000                 // edx = exponent(b)
	jz           Lps2mul_avx_mul_zero

	add          eax, edx
	sub          eax, (127 << 23)                // eax = exponent(a) + exponent(b) - 127

	mov          edx, esi
	shr          esi, 1
	mov          edi, esi
	and          esi, 0x800000
	cmovz        edi, edx
	add          eax, esi
	and          edi, 0x7fffff

	cmp          eax, (1 << 23)
	jl           Lps2mul_avx_out_of_range

	or           eax, ecx
	or           eax, edi

Lps2mul_avx_done:
	vmovd        xmm0, eax
	vbroadcastss xmm0, xmm0                      // Not really necessary, but tests want the result in all lanes to verify multilane vector functions
	ret

Lps2mul_avx_mul_zero:
	mov          eax, ecx                        // return sign
	jmp          Lps2mul_avx_done

Lps2mul_avx_out_of_range:
	mov          edx, ecx
	or           edx, 0x7fffffff                 // edx = sign | 0x7fffffff
	cmp          eax, (-127 << 23)
	mov          eax, ecx
	cmovl        eax, edx                        // return overflow ? sign | 0x7fffffff : sign
	jmp          Lps2mul_avx_done

.balign 16
.globl GNAME(ps2mul_one_sse4)
GNAME(ps2mul_one_sse4):
	movd       eax, xmm0
	movd       edx, xmm1
	pshufb     xmm1, [rip + one_b_shuf]
	pmullw     xmm1, [rip + one_b_shift]    // xmm1 = b << (bit * 2 + 7)
	pshufb     xmm0, [rip + sse_broadcastw_shuf]
	movaps     xmm5, [rip + one_pos]
	pmullw     xmm0, xmm5                   // xmm0 = a << (bit * 2)
	pand       xmm1, [rip + sse_const_7b]   // xmm1 = test = (b << (bit * 2 - 1)) & 7
	movq       xmm4, [rip + booth_table]
	pshufb     xmm4, xmm1                   // xmm4 = booth[test] << 8
	movdqa     xmm3, xmm4
	psraw      xmm4, 8                      // xmm4 = booth[test]
	pmullw     xmm0, xmm4                   // xmm0 = a * booth[test]
	psraw      xmm3, 15                     // xmm3 = booth[test] < 0 ? ~0 : 0
	pand       xmm3, xmm5                   // xmm3 = negate[test]
	psubw      xmm0, xmm3                   // xmm0 = booth(a) (correct negate to invert)
	movd       xmm2, [rip + mask_fff]
	pandn      xmm2, xmm0                   // xmm2 = b5.data & ~0xfffu, b2.data
	pshufd     xmm1, xmm0, 1                // xmm1 = b4.data,           b1.data
	pshufd     xmm4, xmm0, 2                // xmm3 = b6.data,           b3.data
	CSA_SSE a=xmm1, b=xmm2, c=xmm4, tmp=xmm5, link=1
	pxor       xmm5, xmm5
	pblendw    xmm3, xmm5, 0xaa             // mask out negate of b0-b3
	pshufd     xmm4, xmm3, 2                // xmm3 = b6.negate
	movd       xmm5, [rip + mask_800]
	pand       xmm5, xmm0                   // xmm5 = b5.data & 0x800
	por        xmm4, xmm5                   // xmm4 = b6.negate | (b5.data & 0x800)
	paddw      xmm2, xmm4                   // t1.hi += b6.negate | (b5.data & 0x800)
	pshufd     xmm4, xmm0, 3                // xmm3 = b7.data, b0.data
	movd       xmm5, [rip + mask_400]
	pand       xmm5, xmm0                   // xmm5 = b5.data & 0x400
	paddw      xmm5, xmm3                   // xmm5 = (b5.data & 0x400) + b5.negate, 0, xxx...
	por        xmm4, xmm5                   // b7.data |= (b5.data & 0x400) + b5.negate
	movdqa     xmm5, xmm2                   // xmm5 = t1.hi + t1.lo, t0.hi + t0.l
	psubw      xmm5, xmm1                   // xmm5 = t1.hi, t0.hi
	CSA_SSE_LINK l=xmm1, lh=xmm2, c=xmm4, h=xmm5, link=1
	movdqa     xmm5, xmm2                   // xmm5 = t3.hi + t3.lo, t2.hi + t2.lo
	psubw      xmm5, xmm1                   // xmm5 = t3.hi, t2.hi
	pshuflw    xmm0, xmm1, 1                // xmm0 = t2.lo
	pshuflw    xmm4, xmm5, 1                // xmm4 = t2.hi
	CSA_SSE_LINK l=xmm1, lh=xmm2, c=xmm4, h=xmm5, link=1
	movdqa     xmm5, xmm2                   // xmm5 = t4.hi + t4.lo
	psubw      xmm5, xmm1                   // xmm5 = t4.hi
	CSA_SSE_LINK l=xmm1, lh=xmm2, c=xmm0, h=xmm5
	pshufd     xmm3, xmm3, 3
	paddd      xmm2, xmm3                   // t5.hi += b7.negate
	pxor       xmm2, xmm1                   // xmm0 = ps2lo = t5.lo ^ t5.hi

	mov          esi, eax
	mov          edi, edx
	and          esi, 0x7fffff
	and          edi, 0x7fffff
	or           esi, 0x800000
	or           edi, 0x800000
	imul         rsi, rdi                        // rsi = full

	movd         edi, xmm2
	and          edi, 0x8000
	sub          rsi, rdi
	shr          rsi, 23                         // rsi = mc

	mov          ecx, eax
	xor          ecx, edx
	and          ecx, 0x80000000                 // ecx = sign = (a ^ b) & 0x80000000
	and          eax, 0x7f800000                 // eax = exponent(a)
	jz           Lps2mul_sse4_mul_zero
	and          edx, 0x7f800000                 // edx = exponent(b)
	jz           Lps2mul_sse4_mul_zero

	add          eax, edx
	sub          eax, (127 << 23)                // eax = exponent(a) + exponent(b) - 127

	mov          edx, esi
	shr          esi, 1
	mov          edi, esi
	and          esi, 0x800000
	cmovz        edi, edx
	add          eax, esi
	and          edi, 0x7fffff

	cmp          eax, (1 << 23)
	jl           Lps2mul_sse4_out_of_range

	or           eax, ecx
	or           eax, edi

Lps2mul_sse4_done:
	movd         xmm0, eax
	pshufd       xmm0, xmm0, 0                   // Not really necessary, but tests want the result in all lanes to verify multilane vector functions
	ret

Lps2mul_sse4_mul_zero:
	mov          eax, ecx                        // return sign
	jmp          Lps2mul_sse4_done

Lps2mul_sse4_out_of_range:
	mov          edx, ecx
	or           edx, 0x7fffffff                 // edx = sign | 0x7fffffff
	cmp          eax, (-127 << 23)
	mov          eax, ecx
	cmovl        eax, edx                        // return overflow ? sign | 0x7fffffff : sign
	jmp          Lps2mul_sse4_done

// Note: According to uica.uops.info, this isn't actually any faster than the avx version
// (And it'll definitely be slower on Zen 1 where ymm ops are split into two uops.)
.balign 16
.globl GNAME(ps2mul_avx2)
GNAME(ps2mul_avx2):
	vinserti128    ymm1, ymm1, xmm1, 1                  // Broadcast b to ymm1
	vinserti128    ymm0, ymm0, xmm0, 1                  // Broadcast a to ymm0
	vpshufb        ymm6, ymm1, [rip + ymm_b_shuf]
	vpmullw        ymm6, ymm6, [rip + ymm_b_shift_5241] // ymm6 = [l] b << (bit * 2 + 7)
	vbroadcasti128 ymm7, [rip + ymm_b_shuf]
	vpshufb        ymm7, ymm1, ymm7
	vpmullw        ymm7, ymm7, [rip + ymm_b_shift_6370] // ymm7 = [h] b << (bit * 2 + 7)
	vbroadcasti128 ymm5, [rip + ymm_b_shuf + 16]
	vpshufb        ymm5, ymm0, ymm5
	vmovdqa        ymm8, [rip + ymm_one_pos_5241]
	vmovdqa        ymm9, [rip + ymm_one_pos_6370]
	vpmullw        ymm4, ymm8, ymm5                     // ymm5 = [l] a << (bit * 2)
	vpmullw        ymm5, ymm9, ymm5                     // ymm6 = [h] a << (bit * 2)
	vpbroadcastd   ymm2, [rip + const_7b]
	vpand          ymm6, ymm2, ymm6                     // ymm6 = [l] test = (b << (bit * 2 - 1)) & 7
	vpand          ymm7, ymm2, ymm7                     // ymm7 = [h] test = (b << (bit * 2 - 1)) & 7
	vpbroadcastq   ymm2, [rip + booth_table]
	vpshufb        ymm6, ymm2, ymm6                     // ymm6 = [l] booth[test] << 8
	vpshufb        ymm7, ymm2, ymm7                     // ymm6 = [h] booth[test] << 8
	vpsraw         ymm2, ymm6, 8                        // ymm2 = [l] booth[test]
	vpmullw        ymm4, ymm4, ymm2                     // ymm4 = [l] a * booth[test]
	vpsraw         ymm6, ymm6, 15                       // ymm6 = [l] booth[test] < 0 ? ~0 : 0
	vpand          ymm6, ymm8, ymm6                     // ymm6 = [l] negate[test]
	vpsubw         ymm4, ymm4, ymm6                     // ymm4 = [l] booth(a) (correct negate to invert)
	vpsraw         ymm3, ymm7, 8                        // ymm3 = [h] booth[test]
	vpmullw        ymm5, ymm5, ymm3                     // ymm5 = [h] a * booth[test]
	vpsraw         ymm7, ymm7, 15                       // ymm7 = [h] booth[test] < 0 ? ~0 : 0
	vpand          ymm7, ymm9, ymm7                     // ymm7 = [h] negate[test]
	vpsubw         ymm5, ymm5, ymm7                     // ymm5 = [h] booth(a) (correct negate to invert)
	vpbroadcastd   xmm8, [rip + mask_fff]
	vpandn         xmm8, xmm8, xmm4                     // xmm8 = b5.data & ~0xfffu, b2.data
	vextracti128   xmm9, ymm4, 1                        // xmm9 = b4.data,           b1.data
	CSA_AVX_ND     o0=xmm2, o1=xmm3, a=xmm8, b=xmm5, c=xmm9, link=1
	vpbroadcastd   ymm8, [rip + mask_ffff]
	vpand          ymm7, ymm8, ymm7                     // ymm7 = b6.negate, b7.negate
	vpand          xmm6, xmm8, xmm6                     // xmm6 = b5.negate
	vpbroadcastd   xmm8, [rip + mask_800]
	vpand          xmm8, xmm8, xmm4                     // xmm8 = b5.data & 0x800
	vpor           xmm8, xmm8, xmm7                     // xmm8 = b6.negate | (b5.data & 0x800)
	vpaddw         xmm3, xmm8, xmm3                     // t1.hi += b6.negate | (b5.data & 0x800)
	vpbroadcastd   xmm8, [rip + mask_400]
	vpand          xmm4, xmm8, xmm4                     // xmm4 = b5.data & 0x400
	vpaddw         xmm4, xmm4, xmm6                     // xmm4 = (b5.data & 0x400) + b5.negate
	vextracti128   xmm6, ymm5, 1                        // xmm6 = b7.data, b0.data
	vpor           xmm6, xmm6, xmm4                     // b7.data |= (b5.data & 0x400) + b5.negate
	vpsubw         xmm4, xmm3, xmm2                     // Finish CSA for t0 and t1
	CSA_AVX_LINK   l=xmm2, lh=xmm3, c=xmm6, h=xmm4, link=1
	vpsubw         xmm6, xmm3, xmm2                     // Finish CSA for t2 and t3
	vpsrld         xmm5, xmm6, 16                       // xmm5 = t2.hi
	vpsrld         xmm4, xmm2, 16                       // xmm4 = t2.lo
	CSA_AVX_LINK   l=xmm2, lh=xmm3, c=xmm5, h=xmm6, link=1
	vpsubw         xmm6, xmm3, xmm2                     // Finish CSA for t4
	CSA_AVX_LINK   l=xmm2, lh=xmm3, c=xmm4, h=xmm6
	vextracti128   xmm7, ymm7, 1                        // xmm7 = b7.negate
	vpaddd         xmm3, xmm3, xmm7                     // t5.hi += b7.negate
	vpxor          xmm2, xmm2, xmm3                     // xmm2 = ps2lo = t5.lo ^ t5.hi

	vpbroadcastd   xmm8, [rip + mask_mantissa]
	vpand          xmm4, xmm0, xmm8                     // xmm4 = a & 0x7fffff
	vpand          xmm5, xmm1, xmm8                     // xmm5 = b & 0x7fffff
	vpbroadcastd   xmm7, [rip + const_exp_1]
	vpor           xmm4, xmm4, xmm7                     // xmm4 = mantissa(a)
	vpor           xmm5, xmm5, xmm7                     // xmm5 = mantissa(b)
	vpshufd        xmm3, xmm4, 0xf5
	vpmuludq       xmm4, xmm4, xmm5                     // xmm4 = [l] mantissa(a) * mantissa(b)
	vpshufd        xmm5, xmm5, 0xf5
	vpmuludq       xmm5, xmm5, xmm3                     // xmm5 = [h] mantissa(a) * mantissa(b)
	vpshufd        xmm3, xmm5, 0xa0
	vpblendd       xmm3, xmm3, xmm4, 0x5                // xmm3 = mullo(mantissa(a), mantisssa(b))
	vpsrlq         xmm4, xmm4, 16
	vpsllq         xmm5, xmm5, 16
	vpblendd       xmm4, xmm4, xmm5, 0xa                // xmm4 = (mantissa(a) * mantissa(b)) >> 16
	vpandn         xmm3, xmm3, xmm2
	vpbroadcastd   xmm5, [rip + mask_8000]
	vpand          xmm5, xmm5, xmm3                     // xmm5 = ((a * b) & ~ps2lo) & 0x8000
	vpsrld         xmm5, xmm5, 15
	vpsubd         xmm4, xmm4, xmm5                     // xmm4 = ps2mulmantissa(a, b) >> 16

	vpbroadcastd   xmm3, [rip + mask_exponent]
	vpand          xmm2, xmm0, xmm3                     // xmm2 = exponent(a)
	vpxor          xmm0, xmm0, xmm1
	vpand          xmm3, xmm3, xmm1                     // xmm3 = exponent(b)
	vpbroadcastd   xmm5, [rip + mask_rest]
	vpandn         xmm0, xmm5, xmm0                     // xmm0 = sign = (a ^ b) & 0x80000000
	vpxor          xmm1, xmm1, xmm1
	vpcmpeqd       xmm6, xmm1, xmm2
	vpcmpeqd       xmm1, xmm1, xmm3
	vpor           xmm1, xmm1, xmm6                     // xmm1 = exponent(a) == 0 || exponent(b) == 0

	vpaddd         xmm2, xmm2, xmm3                     // xmm2 = exponent(a) + exponent(b)
	vpsrld         xmm6, xmm4, 8
	vpand          xmm9, xmm7, xmm6
	vpsrld         xmm3, xmm4, 7
	vblendvps      xmm4, xmm3, xmm6, xmm4               // if (a * b > 0xffffff) mc >>= 1
	vpand          xmm4, xmm8, xmm4                     // xmm4 = mantissa(c)
	vpbroadcastd   xmm6, [rip + const_exp_n127]
	vpaddd         xmm2, xmm2, xmm6                     // xmm2 = exponent(a) + exponent(b) - 127
	vpaddd         xmm2, xmm9, xmm2                     // if (a * b > 0xffffff) xmm2 += 1
	vpcmpgtd       xmm3, xmm6, xmm2                     // xmm3 = overflow ? ~0 : 0
	vpandn         xmm3, xmm1, xmm3                     // xmm3 = overflow && no zero exponent ? ~0 : 0
	vpand          xmm3, xmm3, xmm5
	vpor           xmm0, xmm0, xmm3                     // if (overflow && no zero exponent) output |= 0x7fffffff

	vpcmpgtd       xmm7, xmm7, xmm2                     // xmm7 = exponent(c) overflowed or underflowed
	vpor           xmm1, xmm1, xmm7                     // xmm1 = any special case
	vpor           xmm2, xmm2, xmm0                     // xmm2 = exponent(c) | sign(c)
	vpor           xmm4, xmm4, xmm2                     // xmm4 = mantissa(c) | exponent(c) | sign(c)
	vpblendvb      xmm0, xmm4, xmm0, xmm1               // xmm0 = special case ? xmm0 : xmm4
	vzeroupper
	ret

// PS2 booth ignores all bits below bit 10
// AVX multiply takes advantage of this by doing booth computations single byte values representing bits 8:15 of the original number
// This allows it to squish the 8x4 booth calculations into 2 4x4 byte vector calculations
.balign 16
.globl GNAME(ps2mul_avx)
GNAME(ps2mul_avx):
	vpslld       xmm7, xmm1, 1
	vmovaps      xmm2, [rip + dup_16_to_32_shuf]
	vpshufb      xmm6, xmm1, xmm2
	vbroadcastss xmm3, [rip + b_shift_1526]
	vpmulhuw     xmm6, xmm6, xmm3                       // xmm6 = b.1526
	vpslld       xmm3, xmm1, 11
	vpblendw     xmm7, xmm7, xmm3, 0xaa                 // xmm7 = b.0437
	vpshufb      xmm4, xmm0, xmm2
	vbroadcastss xmm3, [rip + a_shift_5162]
	vpmullw      xmm4, xmm4, xmm3                       // xmm4 = a.5162
	vpslld       xmm5, xmm0, 22
	vpblendw     xmm5, xmm5, xmm0, 0x55                 // xmm5 = a.4073
	vpshufb      xmm7, xmm7, [rip + shuf_0437_to_0734]  // xmm7 = b.0734
	vbroadcastss xmm3, [rip + const_7b]
	vpand        xmm7, xmm7, xmm3                       // xmm7 = b.0734 booth selection bits
	vpand        xmm6, xmm6, xmm3                       // xmm6 = b.1526 booth selection bits
	vpshufb      xmm5, xmm5, [rip + shuf_4073_to_0734]  // xmm5 = a.0734
	vpshufb      xmm4, xmm4, [rip + bswap16_shuf]       // xmm4 = a.1526
	vmovq        xmm8, [rip + booth_2x_table]
	vmovq        xmm9, [rip + booth_zero_table]
	vpshufb      xmm2, xmm8, xmm7
	vpshufb      xmm3, xmm9, xmm7
	vpand        xmm2, xmm2, xmm5
	vpand        xmm5, xmm5, xmm3
	vpaddb       xmm5, xmm5, xmm2
	vpshufb      xmm2, xmm8, xmm6
	vpshufb      xmm3, xmm9, xmm6
	vpand        xmm2, xmm2, xmm4
	vpand        xmm4, xmm4, xmm3
	vpaddb       xmm4, xmm4, xmm2
	vmovq        xmm8, [rip + booth_neg_table]
	vpshufb      xmm7, xmm8, xmm7                       // xmm7 = 0734 negate
	vpshufb      xmm6, xmm8, xmm6                       // xmm6 = 1526 negate
	vpxor        xmm5, xmm5, xmm7                       // xmm5 = 0734 booth
	vpxor        xmm4, xmm4, xmm6                       // xmm4 = 1526 booth
	vbroadcastss xmm2, [rip + mask_f0ffw]
	vpsrld       xmm3, xmm5, 16                         // xmm3 = 34xx
	vpand        xmm2, xmm2, xmm4                       // xmm2 = 1526 with low bits masked out
	vpsrld       xmm8, xmm2, 16                         // xmm8 = 26xx
	CSA_AVX      a=xmm3, b=xmm2, c=xmm8, tmp=xmm9, addop=vpaddb, subop=vpsubb, link=1
	vbroadcastss xmm9, [rip + mask_c0ff]
	vpand        xmm5, xmm9, xmm5                       // xmm5 = mask unwanted bits from 07
	vbroadcastss xmm9, [rip + mask_10000400]
	vpand        xmm6, xmm9, xmm6                       // xmm6 = b5.negate, b6.negate
	vpand        xmm8, xmm9, xmm4                       // xmm3 = b5.data & 0x400
	vpaddb       xmm8, xmm8, xmm6
	vpor         xmm5, xmm8, xmm5                       // b7.data |= (b5.data & 0x400) + b5.negate
	vbroadcastss xmm8, [rip + mask_800]
	vpand        xmm4, xmm8, xmm4                       // xmm4 = b5.data & 0x800
	vpsrld       xmm6, xmm6, 16                         // xmm6 = b6.negate
	vpor         xmm4, xmm4, xmm6                       // xmm4 = b6.negate | (b5.data & 0x800)
	vpaddb       xmm2, xmm2, xmm4                       // t1.hi += b6.negate | (b5.data & 0x800)
	vpsubb       xmm8, xmm2, xmm3                       // Finish CSA for t0 and t1
	CSA_AVX_LINK l=xmm3, lh=xmm2, c=xmm5, h=xmm8, addop=vpaddb, subop=vpsubb, link=1
	vpsubb       xmm4, xmm2, xmm3                       // Finish CSA for t2 and t3
	vpsllw       xmm5, xmm3, 8                          // xmm2 = t2.lo
	vpsllw       xmm8, xmm4, 8                          // xmm3 = t2.hi
	CSA_AVX_LINK l=xmm3, lh=xmm2, c=xmm8, h=xmm4, addop=vpaddb, subop=vpsubb, link=1
	vpsubb       xmm4, xmm2, xmm3                       // Finish CSA for t4
	CSA_AVX_LINK l=xmm3, lh=xmm2, c=xmm5, h=xmm4, addop=vpaddb, subop=vpsubb
	vbroadcastss xmm4, [rip + mask_4000]
	vpand        xmm7, xmm7, xmm4                       // xmm7 = b7.negate
	vpaddb       xmm2, xmm2, xmm7                       // t5.hi += b7.negate
	vpxor        xmm2, xmm3, xmm2                       // xmm2 = ps2lo = t5.lo ^ t5.hi

	vbroadcastss   xmm8, [rip + mask_mantissa]
	vpand          xmm4, xmm0, xmm8                     // xmm4 = a & 0x7fffff
	vpand          xmm5, xmm1, xmm8                     // xmm5 = b & 0x7fffff
	vbroadcastss   xmm7, [rip + const_exp_1]
	vpor           xmm4, xmm4, xmm7                     // xmm4 = mantissa(a)
	vpor           xmm5, xmm5, xmm7                     // xmm5 = mantissa(b)
	vpshufd        xmm3, xmm4, 0xf5
	vpmuludq       xmm4, xmm4, xmm5                     // xmm4 = [l] mantissa(a) * mantissa(b)
	vpshufd        xmm5, xmm5, 0xf5
	vpmuludq       xmm5, xmm5, xmm3                     // xmm5 = [h] mantissa(a) * mantissa(b)
	vpshufd        xmm3, xmm5, 0xa0
	vpblendw       xmm3, xmm3, xmm4, 0x33               // xmm3 = mullo(mantissa(a), mantisssa(b))
	vpsrlq         xmm4, xmm4, 16
	vpsllq         xmm5, xmm5, 16
	vpblendw       xmm4, xmm4, xmm5, 0xcc               // xmm4 = (mantissa(a) * mantissa(b)) >> 16
	vpandn         xmm3, xmm3, xmm2
	vbroadcastss   xmm5, [rip + mask_8000]
	vpand          xmm5, xmm5, xmm3                     // xmm5 = ((a * b) & ~ps2lo) & 0x8000
	vpsrld         xmm5, xmm5, 15
	vpsubd         xmm4, xmm4, xmm5                     // xmm4 = ps2mulmantissa(a, b) >> 16

	vbroadcastss   xmm3, [rip + mask_exponent]
	vpand          xmm2, xmm0, xmm3                     // xmm2 = exponent(a)
	vpxor          xmm0, xmm0, xmm1
	vpand          xmm3, xmm3, xmm1                     // xmm3 = exponent(b)
	vbroadcastss   xmm5, [rip + mask_rest]
	vpandn         xmm0, xmm5, xmm0                     // xmm0 = sign = (a ^ b) & 0x80000000
	vpxor          xmm1, xmm1, xmm1
	vpcmpeqd       xmm6, xmm1, xmm2
	vpcmpeqd       xmm1, xmm1, xmm3
	vpor           xmm1, xmm1, xmm6                     // xmm1 = exponent(a) == 0 || exponent(b) == 0

	vpaddd         xmm2, xmm2, xmm3                     // xmm2 = exponent(a) + exponent(b)
	vpsrld         xmm6, xmm4, 8
	vpand          xmm9, xmm7, xmm6
	vpsrld         xmm3, xmm4, 7
	vblendvps      xmm4, xmm3, xmm6, xmm4               // if (a * b > 0xffffff) mc >>= 1
	vpand          xmm4, xmm8, xmm4                     // xmm4 = mantissa(c)
	vbroadcastss   xmm6, [rip + const_exp_n127]
	vpaddd         xmm2, xmm2, xmm6                     // xmm2 = exponent(a) + exponent(b) - 127
	vpaddd         xmm2, xmm9, xmm2                     // if (a * b > 0xffffff) xmm2 += 1
	vpcmpgtd       xmm3, xmm6, xmm2                     // xmm3 = overflow ? ~0 : 0
	vpandn         xmm3, xmm1, xmm3                     // xmm3 = overflow && no zero exponent ? ~0 : 0
	vpand          xmm3, xmm3, xmm5
	vpor           xmm0, xmm0, xmm3                     // if (overflow && no zero exponent) output |= 0x7fffffff

	vpcmpgtd       xmm7, xmm7, xmm2                     // xmm7 = exponent(c) overflowed or underflowed
	vpor           xmm1, xmm1, xmm7                     // xmm1 = any special case
	vpor           xmm2, xmm2, xmm0                     // xmm2 = exponent(c) | sign(c)
	vpor           xmm4, xmm4, xmm2                     // xmm4 = mantissa(c) | exponent(c) | sign(c)
	vpblendvb      xmm0, xmm4, xmm0, xmm1               // xmm0 = special case ? xmm0 : xmm4
	ret

.balign 16
.globl GNAME(ps2mul_sse4)
GNAME(ps2mul_sse4):
	movdqa   xmm6, xmm1
	movdqa   xmm7, xmm1
	movaps   xmm2, [rip + dup_16_to_32_shuf]
	movdqa   xmm9, xmm1
	pslld    xmm1, 1
	pshufb   xmm6, xmm2
	pmulhuw  xmm6, [rip + sse_b_shift_1526]  // xmm6 = b.1526
	pslld    xmm7, 11
	pblendw  xmm7, xmm1, 0x55                // xmm7 = b.0437
	movdqa   xmm4, xmm0
	movdqa   xmm8, xmm0
	pshufb   xmm4, xmm2
	pmullw   xmm4, [rip + sse_a_shift_5162]  // xmm4 = a.5162
	pslld    xmm0, 22
	pblendw  xmm0, xmm8, 0x55                // xmm0 = a.4073
	pshufb   xmm7, [rip + shuf_0437_to_0734] // xmm7 = b.0734
	movaps   xmm2, [rip + sse_const_7b]
	pand     xmm7, xmm2                      // xmm7 = b.0734 booth selection bits
	pand     xmm6, xmm2                      // xmm6 = b.1526 booth selection bits
	pshufb   xmm0, [rip + shuf_4073_to_0734] // xmm0 = a.0734
	pshufb   xmm4, [rip + bswap16_shuf]      // xmm4 = a.1526
	movq     xmm3, [rip + booth_zero_table]
	movq     xmm5, [rip + booth_2x_table]
	pshufb   xmm3, xmm7
	pshufb   xmm5, xmm7
	pand     xmm5, xmm0
	pand     xmm3, xmm0
	paddb    xmm5, xmm3
	movq     xmm3, [rip + booth_zero_table]
	movq     xmm1, [rip + booth_2x_table]
	pshufb   xmm3, xmm6
	pshufb   xmm1, xmm6
	pand     xmm3, xmm4
	pand     xmm4, xmm1
	paddb    xmm4, xmm3
	movq     xmm3, [rip + booth_neg_table]
	movq     xmm2, [rip + booth_neg_table]
	pshufb   xmm3, xmm7                      // xmm3 = 0734 negate
	pshufb   xmm2, xmm6                      // xmm2 = 1526 negate
	pxor     xmm5, xmm3                      // xmm5 = 0734 booth
	pxor     xmm4, xmm2                      // xmm4 = 1526 booth
	movaps   xmm0, [rip + sse_mask_f0ffw]
	pand     xmm0, xmm4                      // xmm0 = 1526 with low bits masked out
	movdqa   xmm1, xmm0                      // xmm1 = 1526 with low bits masked out
	psrld    xmm0, 16                        // xmm0 = 26xx
	movdqa   xmm6, xmm5
	psrld    xmm6, 16                        // xmm6 = 34xx
	CSA_SSE  a=xmm0, b=xmm1, c=xmm6, tmp=xmm7, addop=paddb, subop=psubb, link=1
	pand     xmm5, [rip + sse_mask_c0ff]     // xmm5 = mask unwanted bits from 07
	movaps   xmm6, [rip + sse_mask_10000400]
	pand     xmm2, xmm6                      // xmm2 = b5.negate, b6.negate
	pand     xmm6, xmm4                      // xmm6 = b5.data & 0x400
	paddb    xmm6, xmm2
	por      xmm5, xmm6                      // b7.data |= (b5.data & 0x400) + b5.negate
	pand     xmm4, [rip + sse_mask_800]      // xmm4 = b5.data & 0x800
	psrld    xmm2, 16                        // xmm2 = b6.negate
	por      xmm4, xmm2                      // xmm4 = b6.negate | (b5.data & 0x800)
	paddb    xmm1, xmm4                      // t1.hi += b6.negate | (b5.data & 0x800)
	movdqa   xmm7, xmm1                      // xmm7 = t1.hi + t1.lo, t0.hi + t0.lo
	psubb    xmm7, xmm0                      // xmm7 = t1.hi, t0.hi
	CSA_SSE_LINK l=xmm0, lh=xmm1, c=xmm5, h=xmm7, addop=paddb, subop=psubb, link=1
	movdqa   xmm5, xmm0                      // xmm1 = t3.lo
	movdqa   xmm2, xmm1                      // xmm2 = t3.hi + t3.lo
	psubb    xmm1, xmm0                      // xmm5 = t3.hi
	movdqa   xmm7, xmm1                      // xmm7 = t3.hi
	psllw    xmm1, 8                         // xmm5 = t2.hi
	CSA_SSE_LINK l=xmm0, lh=xmm2, c=xmm1, h=xmm7, addop=paddb, subop=psubb, link=1
	psllw    xmm5, 8                         // xmm0 = t2.lo
	movdqa   xmm7, xmm2                      // xmm7 = t4.hi + t4.lo
	psubb    xmm2, xmm0                      // xmm2 = t4.hi
	CSA_SSE_LINK l=xmm0, lh=xmm7, c=xmm5, h=xmm2, addop=paddb, subop=psubb
	pand     xmm3, [rip + sse_mask_4000]     // xmm7 = b7.negate
	paddb    xmm7, xmm3                      // t5.hi += b7.negate
	pxor     xmm0, xmm7                      // xmm0 = ps2lo = t5.lo ^ t5.hi

	movaps   xmm4, [rip + sse_mask_mantissa]
	movaps   xmm5, [rip + sse_mask_mantissa]
	pand     xmm4, xmm8
	pand     xmm5, xmm9
	por      xmm4, [rip + sse_const_exp_1]   // xmm4 = mantissa(a)
	por      xmm5, [rip + sse_const_exp_1]   // xmm5 = mantissa(b)
	pshufd   xmm3, xmm4, 0xf5
	pmuludq  xmm4, xmm5                      // xmm4 = [l] mantissa(a) * mantissa(b)
	pshufd   xmm5, xmm5, 0xf5
	pmuludq  xmm5, xmm3                      // xmm5 = [h] mantissa(a) * mantissa(b)
	pshufd   xmm3, xmm5, 0xa0
	pblendw  xmm3, xmm4, 0x33                // xmm3 = mullo(mantissa(a), mantisssa(b))
	psrlq    xmm4, 16
	psllq    xmm5, 16
	pblendw  xmm4, xmm5, 0xcc                // xmm4 = (mantissa(a) * mantissa(b)) >> 16
	pandn    xmm3, xmm0
	pand     xmm3, [rip + sse_mask_8000]     // xmm3 = ((a * b) & ~ps2lo) & 0x8000
	psrld    xmm3, 15
	psubd    xmm4, xmm3                      // xmm4 = ps2mulmantissa(a, b) >> 16

	movaps   xmm2, [rip + sse_mask_exponent]
	pand     xmm2, xmm8                      // xmm2 = exponent(a)
	pxor     xmm8, xmm9
	movaps   xmm3, [rip + sse_mask_exponent]
	pand     xmm3, xmm9                      // xmm3 = exponent(b)
	pand     xmm8, [rip + sse_mask_sign]     // xmm8 = sign = (a ^ b) & 0x80000000
	pxor     xmm6, xmm6
	pcmpeqd  xmm6, xmm2
	pxor     xmm7, xmm7
	pcmpeqd  xmm7, xmm3
	por      xmm7, xmm6                      // xmm0 = exponent(a) == 0 || exponent(b) == 0

	paddd    xmm2, xmm3                      // xmm2 = exponent(a) + exponent(b)
	movdqa   xmm3, xmm4
	movdqa   xmm0, xmm4
	psrld    xmm4, 8
	movdqa   xmm6, [rip + sse_const_exp_1]
	pand     xmm6, xmm4
	psrld    xmm3, 7
	blendvps xmm3, xmm4, xmm0
	pand     xmm3, [rip + sse_mask_mantissa] // xmm3 = mantissa(c)
	movaps   xmm5, [rip + sse_const_exp_n127]
	paddd    xmm2, xmm5                      // xmm2 = exponent(a) + exponent(b) - 127
	paddd    xmm2, xmm6                      // if (a * b > 0xffffff) xmm2 += 1
	pcmpgtd  xmm5, xmm2                      // xmm5 = overflow ? ~0 : 0
	movdqa   xmm1, xmm7
	pandn    xmm1, xmm5                      // xmm1 = overflow && no zero exponent ? ~0 : 0
	psrld    xmm1, 1
	por      xmm1, xmm8                      // if (overflow && no zero exponent) output |= 0x7fffffff

	movaps   xmm0, [rip + sse_const_exp_1]
	pcmpgtd  xmm0, xmm2                      // xmm0 = exponent(c) overflowed or underflowed
	por      xmm0, xmm7                      // xmm0 = any special case
	por      xmm2, xmm1                      // xmm2 = exponent(c) | sign(c)
	por      xmm3, xmm2                      // xmm3 = mantissa(c) | exponent(c) | sign(c)
	pblendvb xmm3, xmm1, xmm0                // xmm3 = special case ? xmm1 : xmm3
	movdqa   xmm0, xmm3
	ret

.data
.balign 64
one_pos:
//         b5,     b2,     b4,     b1,     b6,     b3,     b7,     b0
.short 0x0400, 0x0010, 0x0100, 0x0004, 0x1000, 0x0040, 0x4000, 0x0001
one_b_shuf:
.byte  1, 128,   0, 1,   0, 1,   0, 1, 1, 128,   0, 1, 1, 128,   0, 1
//     0x0e00, 0x0038, 0x0380, 0x000e, 0x3800, 0x00e0, 0xe000, 0x0003
one_b_shift:
.short 0x0080, 0x0020, 0x0002, 0x0080, 0x0020, 0x0008, 0x0008, 0x0200
booth_table:
.byte 0, 1, 1, 2, -2, -1, -1, 0
mask_fff:
.int 0xfff
mask_400:
.int 0x400
mask_800:
.int 0x800
mask_ffff:
.int 0xffff
mask_8000:
.int 0x8000
mask_mantissa:
.int 0x7fffff
mask_exponent:
.int 0x7f800000
mask_rest:
.int 0x7fffffff
const_7b:
.byte 7, 7, 7, 7
const_exp_1:
.int 1 << 23
const_exp_n127:
.int -127 << 23
b_shift_1526: // Shift right with pmulhuw
.short 0x8000, 0x2000
a_shift_5162: // Shift left with pmullw
.short 0x0004, 0x0010
mask_f0ffw:
.short 0xf0ff, 0xf0ff
mask_10000400:
.short 0x0400, 0x1000
mask_c0ff:
.int 0xc0ff
mask_4000:
.int 0x4000

.balign 8
booth_2x_table:
.byte 0,  0,  0, -1, -1,  0,  0, 0
booth_neg_table:
.byte 0,  0,  0,  0, -1, -1, -1, 0
booth_zero_table:
.byte 0, -1, -1, -1, -1, -1, -1, 0

.balign 16
dup_16_to_32_shuf:
.byte 0, 1, 0, 1, 4, 5, 4, 5, 8, 9, 8, 9, 12, 13, 12, 13
bswap16_shuf:
.byte 1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 13, 12, 15, 14
shuf_0437_to_0734:
.byte 0, 3, 2, 1, 4, 7, 6, 5, 8, 11, 10, 9, 12, 15, 14, 13
shuf_4073_to_0734:
.byte 1, 2, 3, 0, 5, 6, 7, 4, 9, 10, 11, 8, 13, 14, 15, 12
sse_broadcastw_shuf:
.byte 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1
sse_const_7b:
.byte 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7
sse_mask_mantissa:
.int 0x007fffff, 0x007fffff, 0x007fffff, 0x007fffff
sse_mask_exponent:
.int 0x7f800000, 0x7f800000, 0x7f800000, 0x7f800000
sse_mask_sign:
.int 0x80000000, 0x80000000, 0x80000000, 0x80000000
sse_const_exp_1:
.int 1 << 23, 1 << 23, 1 << 23, 1 << 23
sse_const_exp_n127:
.int -127 << 23, -127 << 23, -127 << 23, -127 << 23
sse_b_shift_1526:
.short 0x8000, 0x2000, 0x8000, 0x2000, 0x8000, 0x2000, 0x8000, 0x2000
sse_a_shift_5162:
.short 0x0004, 0x0010, 0x0004, 0x0010, 0x0004, 0x0010, 0x0004, 0x0010
sse_mask_f0ffw:
.short 0xf0ff, 0xf0ff, 0xf0ff, 0xf0ff, 0xf0ff, 0xf0ff, 0xf0ff, 0xf0ff
sse_mask_10000400:
.short 0x0400, 0x1000, 0x0400, 0x1000, 0x0400, 0x1000, 0x0400, 0x1000
sse_mask_c0ff:
.int 0xc0ff, 0xc0ff, 0xc0ff, 0xc0ff
sse_mask_800:
.int 0x0800, 0x0800, 0x0800, 0x0800
sse_mask_4000:
.int 0x4000, 0x4000, 0x4000, 0x4000
sse_mask_8000:
.int 0x8000, 0x8000, 0x8000, 0x8000

.balign 32
ymm_b_shuf: // 5241 uses both, 6370 uses the first 16-byte one duplicated
.byte  1, 128,   0, 1, 5, 128,   4, 5, 9, 128,   8, 9, 13,128, 12, 13
.byte    0, 1,   0, 1,   4, 5,   4, 5,   8, 9,   8, 9, 12, 13, 12, 13
ymm_b_shift_5241:
.short 0x0080, 0x0020, 0x0080, 0x0020, 0x0080, 0x0020, 0x0080, 0x0020
.short 0x0002, 0x0080, 0x0002, 0x0080, 0x0002, 0x0080, 0x0002, 0x0080
ymm_b_shift_6370:
.short 0x0020, 0x0008, 0x0020, 0x0008, 0x0020, 0x0008, 0x0020, 0x0008
.short 0x0008, 0x0200, 0x0008, 0x0200, 0x0008, 0x0200, 0x0008, 0x0200
ymm_one_pos_5241:
.short 0x0400, 0x0010, 0x0400, 0x0010, 0x0400, 0x0010, 0x0400, 0x0010
.short 0x0100, 0x0004, 0x0100, 0x0004, 0x0100, 0x0004, 0x0100, 0x0004
ymm_one_pos_6370:
.short 0x1000, 0x0040, 0x1000, 0x0040, 0x1000, 0x0040, 0x1000, 0x0040
.short 0x4000, 0x0001, 0x4000, 0x0001, 0x4000, 0x0001, 0x4000, 0x0001

#endif // __x86_64__
