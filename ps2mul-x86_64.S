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

.macro CSA a, b, c, tmp
	mov \tmp, \a
	xor \a, \b
	and \tmp, \b
	mov \b, \c
	and \b, \a
	xor \a, \c
	or  \b, \tmp
	add \b, \b
.endm

.macro CSA_AVX a, b, c, tmp, addop=vpaddw
	vpand  \tmp, \a, \b
	vpxor  \a, \a, \b
	vpand  \b, \a, \c
	vpxor  \a, \a, \c
	vpor   \b, \b, \tmp
	\addop \b, \b, \b
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
	CSA a=eax, b=edx, c=edi, tmp=ecx
	or     edx, ebx          // t1.hi |= b6.negate | (b5.data & 0x800)

	BOOTH a=r8d, b=r9d, bit=1, data=ebx, negate=edi, t0=esi,  t0r=rsi, t1=ecx, ar=r8
	BOOTH a=r8d, b=r9d, bit=2, data=ecx, negate=edi, t0=esi,  t0r=rsi, t1=r12d
	BOOTH a=r8d, b=r9d, bit=3, data=edi, negate=esi, t0=r11d, t0r=r11, t1=r12d
	CSA a=ebx, b=ecx, c=edi, tmp=esi

	BOOTH a=r8d, b=r9d, bit=7, data=edi, negate=r11d, t0=esi, t0r=rsi, t1=r12d, calc_neg=1, mask_neg=1
	or     edi, r10d         // b7.data |= (b5.data & 0x400) + b5.negate
	CSA a=eax, b=edx, c=edi, tmp=esi

	// Manual bit=0 booth for b0
	mov    edi, r8d
	mov    r10d, r9d
	and    r10d, 3
	xor    esi, esi
	cmp    r10d, 2
	cmove  esi, edi
	add    edi, esi
	xor    esi, esi
	cmp    r10d, 2
	adc    esi, -1
	xor    edi, esi
	xor    esi, esi
	test   r10d, r10d
	cmovz  edi, esi
	CSA a=ebx, b=ecx, c=edi, tmp=esi

	CSA a=eax, b=edx, c=ecx, tmp=esi
	CSA a=ebx, b=eax, c=edx, tmp=esi

	add    eax, r11d        // t5.hi += b7.negate
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
	vpbroadcastd xmm4, [rip + const_700w]
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
	CSA_AVX a=xmm0, b=xmm1, c=xmm3, tmp=xmm5
	vpbroadcastd xmm5, [rip + mask_ffff]
	vpand        xmm4, xmm4, xmm5                // mask out negate of b0-b3
	vpunpckhqdq  xmm3, xmm4, xmm4                // xmm4 = b6.negate
	vmovd        xmm5, [rip + mask_800]
	vpand        xmm5, xmm5, xmm2                // xmm5 = b5.data & 0x800
	vpor         xmm3, xmm3, xmm5                // xmm3 = b6.negate | (b5.data & 0x800)
	vpor         xmm1, xmm1, xmm3                // t1.hi |= b6.negate | (b5.data & 0x800)
	vpshufd      xmm3, xmm2, 3                   // xmm3 = b7.data, b0.data
	vmovd        xmm5, [rip + mask_400]
	vpand        xmm5, xmm5, xmm2                // xmm5 = b5.data & 0x400
	vpaddw       xmm5, xmm5, xmm4                // xmm5 = (b5.data & 0x400) + b5.negate, 0, xxx...
	vpor         xmm3, xmm3, xmm5                // b7.data |= (b5.data & 0x400) + b5.negate
	CSA_AVX a=xmm0, b=xmm1, c=xmm3, tmp=xmm5
	vpsrld       xmm2, xmm0, 16                  // xmm2 = t2.lo
	vpsrld       xmm3, xmm1, 16                  // xmm3 = t2.hi
	CSA_AVX a=xmm0, b=xmm1, c=xmm3, tmp=xmm5
	CSA_AVX a=xmm0, b=xmm2, c=xmm1, tmp=xmm5
	vpshufd      xmm4, xmm4, 3
	vpaddd       xmm2, xmm2, xmm4                // t5.hi += b7.negate
	vpxor        xmm0, xmm0, xmm2                // xmm0 = ps2lo = t5.lo ^ t5.hi

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
const_700w:
.short 0x700, 0x700

#endif // __x86_64__
