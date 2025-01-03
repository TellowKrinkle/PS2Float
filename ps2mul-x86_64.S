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

.balign 16
.globl GNAME(ps2mul_asm)
GNAME(ps2mul_asm):
	push rbx
	push r12
	push r13
	push r14

	mov   r10d, edi
	mov   r11d, esi
	and   edi, 0x7fffff
	and   esi, 0x7fffff
	or    edi, 0x800000
	or    esi, 0x800000
	mov   r8d, edi
	mov   r9d, esi

	BOOTH a=edi, b=esi, bit=4, data=eax, negate=ecx, t0=ebx, t0r=rbx, t1=edx
	BOOTH a=edi, b=esi, bit=5, data=edx, negate=ecx, t0=ebx, t0r=rbx, t1=r12d, calc_neg=1
	BOOTH a=edi, b=esi, bit=6, data=edi, negate=ebx, t0=esi, t0r=rsi, t1=r12d, calc_neg=1, mask_neg=1, destructive=1
	mov   r12d, edx
	and   r12d, 0x400
	add   r12d, ecx         // r12d = (b5.data & 0x400) + b5.negate
	mov   ecx, edx
	and   ecx, 0x800
	or    ebx, ecx          // ebx = b6.negate | (b5.data & 0x800)
	and   edx, ~0xfff
	CSA a=eax, b=edx, c=edi, tmp=ecx
	or    edx, ebx          // t1.hi |= b6.negate | (b5.data & 0x800)

	BOOTH a=r8d, b=r9d, bit=1, data=ebx, negate=edi, t0=esi,  t0r=rsi, t1=ecx, ar=r8
	BOOTH a=r8d, b=r9d, bit=2, data=ecx, negate=edi, t0=esi,  t0r=rsi, t1=r14d
	BOOTH a=r8d, b=r9d, bit=3, data=edi, negate=esi, t0=r13d, t0r=r13, t1=r14d
	CSA a=ebx, b=ecx, c=edi, tmp=esi

	BOOTH a=r8d, b=r9d, bit=7, data=edi, negate=r13d, t0=esi, t0r=rsi, t1=r14d, calc_neg=1, mask_neg=1
	or    edi, r12d         // b7.data |= (b5.data & 0x400) + b5.negate
	CSA a=eax, b=edx, c=edi, tmp=esi

	// Manual bit=0 booth for b0
	mov    edi, r8d
	imul   r8, r9           // r8 = full
	and    r9d, 3
	xor    esi, esi
	cmp    r9d, 2
	cmove  esi, edi
	add    edi, esi
	xor    esi, esi
	cmp    r9d, 2
	adc    esi, -1
	xor    edi, esi
	xor    esi, esi
	test   r9d, r9d
	cmovz  edi, esi
	CSA a=ebx, b=ecx, c=edi, tmp=esi

	CSA a=eax, b=edx, c=ecx, tmp=esi
	CSA a=ebx, b=eax, c=edx, tmp=esi

	add    eax, r13d        // t5.hi += b7.negate
	and    ebx, ~0x7fff     // t5.lo &= ~0x7fffu
	add    eax, ebx         // ps2lo = t5.lo + t5.hi

	and    eax, 0x8000
	sub    r8, rax
	shr    r8, 23           // r8 = mc

	mov    eax, r10d
	mov    edx, r11d
	and    eax, 0x7f800000
	setz   r13b
	and    edx, 0x7f800000
	setz   r14b
	or     r14b, r13b       // r14b = !ea || !eb

	add    eax, edx
	sub    eax, (127 << 23)

	xor    r10d, r11d
	and    r10d, 0x80000000
	mov    esi, r10d
	or     esi, 0x7fffffff  // esi = sign | 0x7fffffff

	cmp    eax, (-128 << 23)
	setge  dl
	or     dl, r14b
	cmovnz esi, r10d        // if (ec <= 0xff) esi = sign

	mov    edi, r8d
	shr    edi, 1
	mov    edx, edi
	and    edx, 0x800000
	cmovz  edi, r8d
	add    eax, edx
	and    edi, 0x7fffff

	cmp    eax, (1 << 23)
	setl   dl
	or     dl, r14b

	or     eax, edi
	or     eax, r10d
	test   dl, dl
	cmovnz eax, esi

	pop r14
	pop r13
	pop r12
	pop rbx
	ret

#endif // __x86_64__
