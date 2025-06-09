#ifdef __x86_64__

.intel_syntax noprefix
.text
#ifdef __APPLE__
#define GNAME(x) _##x
#else
#define GNAME(x) x
#endif

// General algorithm notes:
// On non-AVX512, the CSA high result is left as a + b + c (rather than a + b + c - lo).
// This allows the CSA calculation of hi to save an instruction
// This means that the calculation of `test` in quotientSelect changes from ((lo & ~mask) + hi) | (lo & mask) to (hl - (lo & mask)) | (lo & mask)

// Prepares the test variable for quotient select
// c0 and s0 are the carry+sum and sum from the previous iteration
// c1 and s1 are the carry+sum and sum from the current iteration
// qd is the previous quotient bit
// The result is placed in c0, and s0 is destroyed.
.macro QSEL1 c1, s1, c0, s0, qd
	test   \qd, \qd
	cmovnz \s0, \s1
	cmovnz \c0, \c1
	and    \s0, (1 << 24) - 1
	sub    \c0, \s0
	or     \c0, \s0
.endm

// Calculates the next quotient bit (negated) and the associated dividend adjustment
// c0 is the previous iteration's carry+sum, which will have the negation bit added to it
// bp and bn are the positive and inverted mantissa of the divisor
// qd and qb are the dword and byte versions of the output quotient bit
// td and tb are the dword and byte versions of a temporary register
// c1 should contain the output of a previous QSEL1
// s1 will be filled with the dividend adjustment value
.macro QSEL2 c1, s1, c0, bp, bn, qd, qb, td, tb
	xor   \s1, \s1
	xor   \td, \td
	xor   \qd, \qd
	cmp   \c1, (1 << 23) - 1
	setg  \tb
	cmovg \s1, \bn
	add   \c0, \td
	cmp   \c1, ~0 << 24
	setl  \qb
	cmovl \s1, \bp
	sub   \qd, \td
.endm

// Calculate a carry-save addition
// c0 and s0 are the incoming carry+sum and sum
// c1 and s1 are the outgoing carry+sum and sum
// t0 is a temporary register
// c0q and s1q are the qword versions of c0 and s1
// The third value for the CSA should be placed in s1
.macro CSA_LINK c1, s1, c0, s0, t0, c0q, s1q
	mov \t0, \c0
	sub \t0, \s0
	xor \t0, \s0
	lea \c1, [\s1q + \c0q]
	xor \s1, \t0
.endm

.balign 16
.globl GNAME(ps2div_asm)
GNAME(ps2div_asm):
	push  rbx
	push  r12
	push  r13

	mov   r10d, edi
	mov   r11d, esi
	and   edi, 0x7fffff
	and   esi, 0x7fffff
	or    edi, 0x800000
	or    esi, 0x800000
	shl   edi, 2
	shl   esi, 2
	mov   r8d, esi
	not   esi

	// CSA_LINK
	add   edi, 1
	lea   ebx, [rdi + rsi]
	xor   edi, esi

	// QSEL1
	mov   ecx, edi
	and   ecx, (1 << 24) - 1
	mov   edx, ebx
	sub   edx, ecx
	or    edx, ecx

	add   edi, edi   // current.sum <<= 1
	add   ebx, ebx   // current.carry <<= 1

	// QSEL2, known output 0 or 1
	xor   r12d, r12d
	xor   eax, eax
	cmp   edx, (1 << 23) - 1
	setg  r12b
	cmovg eax, esi
	add   ebx, r12d

	CSA_LINK c1=edx, s1=eax, c0=ebx, s0=edi, t0=ecx, c0q=rbx, s1q=rax
	QSEL1    c1=edx, s1=eax, c0=ebx, s0=edi, qd=r12d

	add   r12d, 2    // quotient = (1 << 1) + quotientBit
	mov   r13d, 11   // 11x2 iterations + 2 above and 1 below = 25
0:
	add   eax, eax   // current.sum <<= 1
	add   edx, edx   // current.carry <<= 1
	QSEL2    c1=ebx, s1=edi, c0=edx, bp=r8d, bn=esi, qd=r9d, qb=r9b, td=ecx, tb=cl
	add   r12d, r12d // quotient = quotient << 1
	sub   r12d, r9d  // quotient += quotientBit
	CSA_LINK c1=ebx, s1=edi, c0=edx, s0=eax, t0=ecx, c0q=rdx, s1q=rdi
	QSEL1    c1=ebx, s1=edi, c0=edx, s0=eax, qd=r9d

	add   edi, edi   // current.sum <<= 1
	add   ebx, ebx   // current.carry <<= 1
	QSEL2    c1=edx, s1=eax, c0=ebx, bp=r8d, bn=esi, qd=r9d, qb=r9b, td=ecx, tb=cl
	add   r12d, r12d // quotient = quotient << 1
	sub   r12d, r9d  // quotient += quotientBit
	CSA_LINK c1=edx, s1=eax, c0=ebx, s0=edi, t0=ecx, c0q=rbx, s1q=rax
	QSEL1    c1=edx, s1=eax, c0=ebx, s0=edi, qd=r9d

	dec r13d
	jnz 0b

	xor   eax, eax
	xor   edx, edx
	cmp   ebx, (1 << 23) - 1
	setg  dl
	cmp   ebx, ~0 << 24
	setl  al
	sub   edx, eax
	add   r12d, r12d
	add   edx, r12d

	mov   eax, r10d
	xor   eax, r11d
	and   eax, 0x80000000

	and   r11d, 0x7f800000
	jz    2f
	and   r10d, 0x7f800000
	jz    1f
	sub   r10d, r11d
	add   r10d, 126 << 23

	lea   ecx, [r10 + (1 << 23)]
	mov   ebx, edx
	shr   ebx, 1
	cmp   edx, 1 << 24
	cmovb ecx, r10d
	cmovb ebx, edx
	test  ecx, ecx
	jle   3f

	or    eax, ecx
	and   ebx, 0x7fffff
	or    eax, ebx

1:
	pop   r13
	pop   r12
	pop   rbx
	ret

2: // Div 0
	or    eax, 0x7fffffff
	jmp   1b

3: // Overflow / Underflow
	mov   edx, eax
	or    edx, 0x7fffffff
	cmp   ecx, -128 << 23
	cmovl eax, edx
	jmp   1b

// Prepares the test variable for quotient select
// c0 and s0 are the carry+sum and sum from the previous iteration
// c1 and s1 are the carry+sum and sum from the current iteration
// qnz is a mask indicating if the previous quotient bit was nonzero
// km is a register containing 0xff000000
// The result is placed in c0, and s0 is destroyed.
.macro QSEL1_AVX c1, s1, c0, s0, qnz, km
	vpblendvb \s0, \s0, \s1, \qnz
	vpblendvb \c0, \c0, \c1, \qnz
	vpandn    \s0, \km, \s0
	vpsubd    \c0, \c0, \s0
	vpor      \c0, \c0, \s0
.endm

// Calculates the next quotient bit and the associated dividend adjustment
// c0 is the previous iteration's carry+sum, which will have the negation bit added to it
// bp is the mantissa of the divisor
// qv is the output quotient bit and qn is an output value indicating whether qv is nonzero
// t0 is a temporary register
// kp is a register containing 0x007fffff (positive compare value)
// kn is a register containing 0xff000000 (negative compare value)
// c1 should contain the output of a previous QSEL1
// s1 will be filled with the dividend adjustment value
.macro QSEL2_AVX c1, s1, c0, bp, kp, kn, qv, qn, t0
	vpcmpgtd \t0, \c1, \kp // t0 = quotientBit == 1
	vpcmpgtd \qv, \kn, \c1 // qv = quotiontBit == -1
	vpor     \qn, \t0, \qv // qn = quotientBit != 0
	vpxor    \s1, \bp, \t0 // s1 = quotientBit == 1 ? ~bm : bm
	vpand    \s1, \qn, \s1 // s1 = add
	vpsubd   \c0, \c0, \t0 // c0 += quotientBit == 1
	vpsubd   \qv, \qv, \t0 // qv = quotientBit
.endm

// Calculate a carry-save addition
// c0 and s0 are the incoming carry+sum and sum
// c1 and s1 are the outgoing carry+sum and sum
// t0 is a temporary register
// The third value for the CSA should be placed in s1
.macro CSA_LINK_AVX c1, s1, c0, s0, t0
	vpsubd \t0, \c0, \s0
	vpxor  \t0, \t0, \s0
	vpaddd \c1, \s1, \c0
	vpxor  \s1, \s1, \t0
.endm

.balign 16
.globl GNAME(ps2div_one_avx)
GNAME(ps2div_one_avx):
	vbroadcastss xmm7, [rip + mask_mantissa]
	vbroadcastss xmm2, [rip + const_exp_1]
	vmovd        ecx, xmm0
	vmovd        edx, xmm1
	vpand        xmm0, xmm0, xmm7
	vpand        xmm1, xmm1, xmm7
	vpor         xmm0, xmm0, xmm2
	vpor         xmm1, xmm1, xmm2
	vpslld       xmm0, xmm0, 2
	vpslld       xmm9, xmm1, 2
	vbroadcastss xmm8, [rip + mask_ff000000]

	// CSA_LINK_AVX
	vbroadcastss xmm3, [rip + const_1]
	vpaddd       xmm3, xmm3, xmm0
	vpcmpeqd     xmm1, xmm1, xmm1
	vpxor        xmm1, xmm9, xmm1
	vpxor        xmm2, xmm1, xmm3
	vpaddd       xmm3, xmm3, xmm1

	// QSEL1_AVX
	vpandn       xmm0, xmm8, xmm2
	vpsubd       xmm1, xmm3, xmm0
	vpor         xmm1, xmm1, xmm0

	vpaddd       xmm2, xmm2, xmm2 // current.sum <<= 1
	vpaddd       xmm3, xmm3, xmm3 // current.carry <<= 1

	// QSEL2_AVX, known output 0 or 1
	vpcmpgtd     xmm5, xmm1, xmm7 // xmm5 = -quotientBit
	vpsubd       xmm3, xmm3, xmm5 // xmm3 += quotientBit == 1
	vpandn       xmm0, xmm9, xmm5 // xmm0 = add

	CSA_LINK_AVX c1=xmm1, s1=xmm0, c0=xmm3, s0=xmm2, t0=xmm4
	QSEL1_AVX    c1=xmm1, s1=xmm0, c0=xmm3, s0=xmm2, qnz=xmm5, km=xmm8

	vbroadcastss xmm6, [rip + const_2]
	vpsubd       xmm6, xmm6, xmm5 // quotient = (1 << 1) + quotientBit
	mov          esi, 11
0:
	vpaddd       xmm0, xmm0, xmm0 // current.sum <<= 1
	vpaddd       xmm1, xmm1, xmm1 // current.carry <<= 1
	QSEL2_AVX    c1=xmm3, s1=xmm2, c0=xmm1, bp=xmm9, kp=xmm7, kn=xmm8, qv=xmm5, qn=xmm10, t0=xmm4
	vpaddd       xmm6, xmm6, xmm6 // quotient = quotient << 1
	vpaddd       xmm6, xmm6, xmm5 // quotient += quotientBit
	CSA_LINK_AVX c1=xmm3, s1=xmm2, c0=xmm1, s0=xmm0, t0=xmm4
	QSEL1_AVX    c1=xmm3, s1=xmm2, c0=xmm1, s0=xmm0, qnz=xmm10, km=xmm8

	vpaddd       xmm2, xmm2, xmm2 // current.sum <<= 1
	vpaddd       xmm3, xmm3, xmm3 // current.carry <<= 1
	QSEL2_AVX    c1=xmm1, s1=xmm0, c0=xmm3, bp=xmm9, kp=xmm7, kn=xmm8, qv=xmm5, qn=xmm10, t0=xmm4
	vpaddd       xmm6, xmm6, xmm6 // quotient = quotient << 1
	vpaddd       xmm6, xmm6, xmm5 // quotient += quotientBit
	CSA_LINK_AVX c1=xmm1, s1=xmm0, c0=xmm3, s0=xmm2, t0=xmm4
	QSEL1_AVX    c1=xmm1, s1=xmm0, c0=xmm3, s0=xmm2, qnz=xmm10, km=xmm8

	dec          esi
	jnz          0b

	vpcmpgtd     xmm1, xmm3, xmm7
	vpcmpgtd     xmm0, xmm8, xmm3
	vpsubd       xmm0, xmm0, xmm1
	vpaddd       xmm6, xmm6, xmm6
	vpaddd       xmm6, xmm6, xmm0
	vmovd        esi,  xmm6

	mov          eax, ecx
	xor          eax, edx
	and          eax, 0x80000000

	and          edx, 0x7f800000
	jz           2f
	and          ecx, 0x7f800000
	jz           1f
	sub          ecx, edx
	add          ecx, 126 << 23

	lea          edx, [rcx + (1 << 23)]
	mov          edi, esi
	shr          edi, 1
	cmp          esi, 1 << 24
	cmovb        edx, ecx
	cmovb        edi, esi
	test         edx, edx
	jle          3f

	or           eax, edx
	and          edi, 0x7fffff
	or           eax, edi

1:
	vmovd        xmm0, eax
	vbroadcastss xmm0, xmm0
	ret

2: // Div 0
	or    eax, 0x7fffffff
	jmp   1b

3: // Overflow / Underflow
	mov   ecx, eax
	or    ecx, 0x7fffffff
	cmp   edx, -128 << 23
	cmovl eax, ecx
	jmp   1b

.data
.balign 64
mask_ff000000:
.int 0xff000000
mask_mantissa:
.int 0x7fffff
const_1:
.int 1
const_2:
.int 2
const_exp_1:
.int 1 << 23
#endif // __x86_64__
