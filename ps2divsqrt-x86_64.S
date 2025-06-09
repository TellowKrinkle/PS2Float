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

#endif // __x86_64__
