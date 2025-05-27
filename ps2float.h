#include <stdint.h>

#ifdef __x86_64__
#include <immintrin.h>
#endif

#ifdef __cplusplus
extern "C" {
#endif

/// Add two PS2 floating point numbers.  Requires floating point mode set to flush denormals and round towards zero.
uint32_t ps2add(uint32_t a, uint32_t b);
/// Add two PS2 floating point numbers.  Works regardless of floating point mode.
uint32_t ps2add_int(uint32_t a, uint32_t b);
static inline uint32_t ps2sub(uint32_t a, uint32_t b) { return ps2add(a, b ^ 0x80000000); }
/// Multiply two PS2 floating point numbers.
uint32_t ps2mul(uint32_t a, uint32_t b);
/// Divide two PS2 floating point numbers
uint32_t ps2div(uint32_t a, uint32_t b);
/// Get the square root of a PS2 floating point number
uint32_t ps2sqrt(uint32_t a);

#ifdef __x86_64__
uint32_t ps2add_asm(uint32_t a, uint32_t b);
uint32_t ps2add_int_asm(uint32_t a, uint32_t b);
uint32_t ps2mul_asm(uint32_t a, uint32_t b);

__m128i ps2add_avx2(__m128i a, __m128i b);
__m128i ps2add_avx(__m128i a, __m128i b);
__m128i ps2add_sse4(__m128i a, __m128i b);
__m128i ps2add_int_avx(__m128i a, __m128i b);
__m128i ps2add_int_sse4(__m128i a, __m128i b);
__m128i ps2mul_one_avx2(__m128i a, __m128i b);
__m128i ps2mul_one_avx(__m128i a, __m128i b);
__m128i ps2mul_one_sse4(__m128i a, __m128i b);
__m128i ps2mul_avx2(__m128i a, __m128i b);
__m128i ps2mul_avx(__m128i a, __m128i b);
__m128i ps2mul_sse4(__m128i a, __m128i b);
#endif

#ifdef __cplusplus
} // extern "C"
#endif
