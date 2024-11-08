.intel_syntax

.align 4
.globl _ps2add_asm
_ps2add_asm:
	mov    r8d, 0x7fffffff # r8d = 0x7fffffff
	mov    eax, edi
	mov    edx, esi
	and    eax, r8d        # eax = a & 0x7fffffff
	and    edx, r8d        # edx = b & 0x7fffffff
	mov    ecx, edi
	cmp    eax, edx        # if (eax < edx)
	cmovb  edi, esi        #   swap esi, edi
	cmovb  esi, ecx
	mov    eax, edi
	shr    eax, 23         # eax = a >> 23
	xor    edx, edx
	mov    ecx, (2 << 23)
	cmp    al, 254
	cmovae edx, ecx        # edx = eax >= 254 ? (2 << 23) : 0
	mov    ecx, esi
	shr    ecx, 23         # ecx = b >> 23
	sub    eax, ecx        # eax = (a >> 23) - (b >> 23)
	sub    edi, edx        # a -= adjust
	sub    esi, edx        # b -= adjust
	lea    ecx, [rax - 1]  # ecx = shift - 1
	mov    r9d, ~0
	shl    r9d, cl         # r9d = ~0u >> (shift - 1)
	and    r9d, esi        # r9d = b & (~0u >> (shift - 1))
	mov    ecx, esi
	and    ecx, 0x80000000 # ecx = b & 0x8000000
	cmp    al, 2           # if (shift >= 2)
	cmovae esi, r9d        #   b = r9d
	cmp    al, 25          # if (shift >= 25)
	cmovae esi, ecx        #   b = ecx
	movd   xmm0, edi
	movd   xmm1, esi
	addss  xmm0, xmm1
	movd   eax, xmm0       # rax = a * b
	or     r8d, eax        # r8d = rax | 0x7fffffff
	add    eax, edx        # eax += adjust
	cmovo  eax, r8d        # if (overflow) eax = r8d
	ret

.align 4
.globl _ps2add_avx2
_ps2add_avx2:
	vbroadcastss xmm5, [rip + mask_rest]
	vpand        xmm2, xmm5, xmm0
	vpand        xmm3, xmm5, xmm1
	vpcmpgtd     xmm3, xmm3, xmm2
	vpblendvb    xmm6, xmm0, xmm1, xmm3
	vpblendvb    xmm7, xmm1, xmm0, xmm3
	vbroadcastss xmm4, [rip + mask_exponent]
	vpand        xmm0, xmm6, xmm4
	vpand        xmm1, xmm7, xmm4
	vbroadcastss xmm4, [rip + const_exp_253]
	vpcmpgtd     xmm3, xmm0, xmm4
	vbroadcastss xmm4, [rip + const_exp_2]
	vpand        xmm3, xmm3, xmm4
	vpsubd       xmm0, xmm0, xmm1
	vpsubd       xmm6, xmm6, xmm3
	vpsubd       xmm7, xmm7, xmm3
	vpcmpeqd     xmm1, xmm1, xmm1
	vbroadcastss xmm4, [rip + const_exp_1]
	vpcmpgtd     xmm2, xmm0, xmm4
	vpsubd       xmm4, xmm0, xmm4
	vpsrld       xmm4, xmm4, 23
	vpsllvd      xmm1, xmm1, xmm4
	vpand        xmm1, xmm1, xmm7
	vbroadcastss xmm4, [rip + mask_sign]
	vpand        xmm4, xmm4, xmm7
	vpblendvb    xmm7, xmm7, xmm1, xmm2
	vbroadcastss xmm1, [rip + const_exp_24]
	vpcmpgtd     xmm0, xmm0, xmm1
	vpblendvb    xmm7, xmm7, xmm4, xmm0
	vaddps       xmm0, xmm6, xmm7
	vorps        xmm1, xmm5, xmm0
	vpaddd       xmm2, xmm0, xmm3
	vpxor        xmm3, xmm0, xmm2
	vblendvps    xmm0, xmm2, xmm1, xmm3
	ret

.align 4
.globl _ps2add_avx
_ps2add_avx:
	vbroadcastss xmm5, [rip + mask_rest]
	vpand        xmm2, xmm5, xmm0
	vpand        xmm3, xmm5, xmm1
	vpcmpgtd     xmm3, xmm3, xmm2
	vpblendvb    xmm6, xmm0, xmm1, xmm3
	vpblendvb    xmm7, xmm1, xmm0, xmm3
	vbroadcastss xmm4, [rip + mask_exponent]
	vpand        xmm0, xmm6, xmm4
	vpand        xmm1, xmm7, xmm4
	vbroadcastss xmm4, [rip + const_exp_253]
	vpcmpgtd     xmm3, xmm0, xmm4
	vbroadcastss xmm4, [rip + const_exp_2]
	vpand        xmm3, xmm3, xmm4
	vpsubd       xmm0, xmm0, xmm1
	vpsubd       xmm6, xmm6, xmm3
	vpsubd       xmm7, xmm7, xmm3
	vbroadcastss xmm4, [rip + const_fp_half]
	vpaddd       xmm4, xmm4, xmm0
	vcvttps2dq   xmm4, xmm4
	vpxor        xmm2, xmm2, xmm2
	vpsubd       xmm2, xmm2, xmm4
	vpand        xmm1, xmm2, xmm7
	vbroadcastss xmm4, [rip + const_exp_1]
	vpcmpgtd     xmm5, xmm0, xmm4
	vbroadcastss xmm4, [rip + mask_sign]
	vpand        xmm4, xmm4, xmm7
	vpblendvb    xmm7, xmm7, xmm1, xmm5
	vbroadcastss xmm1, [rip + const_exp_24]
	vpcmpgtd     xmm0, xmm0, xmm1
	vpblendvb    xmm7, xmm7, xmm4, xmm0
	vaddps       xmm0, xmm6, xmm7
	vorps        xmm1, xmm5, xmm0
	vpaddd       xmm2, xmm0, xmm3
	vpxor        xmm3, xmm0, xmm2
	vblendvps    xmm0, xmm2, xmm1, xmm3
	ret

.align 4
.globl _ps2add_sse4
_ps2add_sse4:
	movdqa   xmm6, xmm0
	movdqa   xmm7, xmm1
	movdqa   xmm2, [rip + sse_mask_rest]
	pand     xmm2, xmm0
	movdqa   xmm0, [rip + sse_mask_rest]
	pand     xmm0, xmm1
	pcmpgtd  xmm0, xmm2
	pblendvb xmm7, xmm6, xmm0
	pblendvb xmm6, xmm1, xmm0
	movdqa   xmm0, [rip + sse_mask_exponent]
	movdqa   xmm1, [rip + sse_mask_exponent]
	pand     xmm0, xmm6
	pand     xmm1, xmm7
	movdqa   xmm3, xmm0
	pcmpgtd  xmm3, [rip + sse_const_exp_253]
	pand     xmm3, [rip + sse_const_exp_2]
	psubd    xmm0, xmm1
	psubd    xmm6, xmm3
	psubd    xmm7, xmm3
	movdqa   xmm5, xmm0
	movdqa   xmm2, [rip + sse_const_fp_half]
	paddd    xmm2, xmm0
	cvttps2dq xmm2, xmm2
	pxor     xmm1, xmm1
	psubd    xmm1, xmm2
	pand     xmm1, xmm7
	pcmpgtd  xmm0, [rip + sse_const_exp_1]
	movdqa   xmm4, [rip + sse_mask_sign]
	pand     xmm4, xmm7
	pblendvb xmm7, xmm1, xmm0
	movdqa   xmm0, xmm5
	pcmpgtd  xmm0, [rip + sse_const_exp_24]
	pblendvb xmm7, xmm4, xmm0
	addps    xmm6, xmm7
	movdqa   xmm0, xmm6
	paddd    xmm3, xmm6
	orps     xmm6, [rip + sse_mask_rest]
	pxor     xmm0, xmm3
	blendvps xmm3, xmm6, xmm0
	movaps   xmm0, xmm3
	ret

.align 6
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

.align 5
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
