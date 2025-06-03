#include <Metal/Metal.h>
#include <simd/simd.h>
#include <algorithm>
#include <fenv.h>

typedef uint64_t u64;
typedef uint32_t u32;
typedef uint16_t u16;

asm(
	".section __TEXT,__cstring\n\t"
	".globl _DIVCODE\n\t"
	"_DIVCODE:\n\t"
	".incbin \"" DIV_SQRT_FILE_PATH "\"\n\t"
	".byte 0\n\t"
);

extern const char DIVCODE[];

static NSString* const DIVHEAD = @R"(
#define CONSTLOOP _Pragma("unroll")

/// Get the mantissa of a float, as a 24-bit unsigned integer
static inline uint32_t mantissa(uint32_t x) {
	return (x & 0x7fffff) | 0x800000;
}

/// Get the raw (biased) exponent of a float, as an 8-bit unsigned integer
static uint32_t exponent(uint32_t x) {
	return (x >> 23) & 0xff;
}
)";

static NSString* const DIVTAIL = @R"(
static constexpr constant uint NFAILURES = 255;

struct ResultBuffer {
	metal::atomic_uint count;
	uint4 failures[NFAILURES];
};

struct ConstantData {
	uint dividend;
	uint divisor;
};

kernel void divtest(uint pos [[thread_position_in_grid]], device const uint* data [[buffer(0)]], device ResultBuffer& results [[buffer(1)]], constant ConstantData& cb [[buffer(2)]]) {
	uint expected = data[pos];
	uint res = ps2div(cb.dividend + pos, cb.divisor);
	if (res != expected) {
		uint idx = metal::atomic_fetch_add_explicit(&results.count, 1, metal::memory_order_relaxed);
		if (idx < NFAILURES) {
			results.failures[idx] = uint4(cb.dividend + pos, cb.divisor, res, expected);
		}
	}
}
)";

static constexpr uint32_t NFAILURES = 255;
static constexpr uint32_t ELEM_SIZE = 4;

struct MetalDivTest {
	id<MTLDevice> dev = nil;
	id<MTLCommandQueue> queue = nil;
	id<MTLComputePipelineState> pipe = nil;
	id<MTLCommandBuffer> last = nil;
	id<MTLBuffer> results[2];
	id<MTLBuffer> data[2];
	id<MTLCaptureScope> scope;

	MetalDivTest() {
		@autoreleasepool {
			dev = MTLCreateSystemDefaultDevice();
			if (!dev) {
				auto devs = MTLCopyAllDevices();
				if ([devs count] > 0)
					dev = devs[0];
			}
			NSString* div = [[@(DIVCODE) stringByReplacingOccurrencesOfString:@"#include \"ps2float.h\"" withString:DIVHEAD] stringByAppendingString:DIVTAIL];
			NSError* err = nil;
			id<MTLLibrary> lib = [dev newLibraryWithSource:div options:nil error:&err];
			if (err) {
				dev = nil;
				fprintf(stderr, "Failed to compile library: %s\n", [[err localizedDescription] UTF8String]);
				return;
			}
			pipe = [dev newComputePipelineStateWithFunction:[lib newFunctionWithName:@"divtest"] error:&err];
			if (err) {
				dev = nil;
				fprintf(stderr, "Failed to compile shader: %s\n", [[err localizedDescription] UTF8String]);
				return;
			}
			queue = [dev newCommandQueue];
			for (id<MTLBuffer> __strong& res : results) {
				res = [dev newBufferWithLength:(NFAILURES + 1) * 16 options:MTLResourceStorageModeShared];
				*(uint32_t *)[res contents] = 0;
				[res setLabel:[NSString stringWithFormat:@"Result Buffer %zd", &res - results]];
			}
			for (id<MTLBuffer> __strong& buf : data) {
				buf = [dev newBufferWithLength:65536 options:MTLResourceStorageModeManaged];
				[buf setLabel:[NSString stringWithFormat:@"Data Buffer %zd", &buf - data]];
			}
			scope = [[MTLCaptureManager sharedCaptureManager] newCaptureScopeWithCommandQueue:queue];
			[scope setLabel:@"Run"];
		}
	}

	bool processLast() {
		uint32_t nfails = 0;
		if (id<MTLCommandBuffer> last = this->last) {
			[last waitUntilCompleted];
			uint32_t* fails = static_cast<uint32_t*>([results[1] contents]);
			nfails = std::min(*fails, NFAILURES);
			for (uint32_t i = 0; i < nfails; i++) {
				uint32_t* ptr = fails + 4 + i * 4;
				printf("%08x / %08x =[Metal] %08x != %08x\n", ptr[0], ptr[1], ptr[2], ptr[3]);
			}
			*fails = 0;
			this->last = nil;
		}
		return nfails == 0;
	}

	void* prepareNextBuffer(size_t count) {
		if ([data[0] length] < count * ELEM_SIZE) {
			id<MTLBuffer> old = data[0];
			data[0] = [dev newBufferWithLength:count * ELEM_SIZE options:MTLResourceStorageModeManaged];
			[data[0] setLabel:[old label]];
		}
		return [data[0] contents];
	}

	bool process(size_t count, uint32_t dividend, uint32_t divisor) {
		if (!dev)
			return false;
		bool ok = true;
		@autoreleasepool {
			[data[0] didModifyRange:NSMakeRange(0, count * ELEM_SIZE)];
			[scope beginScope];
			id<MTLCommandBuffer> cb = [queue commandBuffer];
			[cb setLabel:@"Divide"];
			id<MTLComputeCommandEncoder> enc = [cb computeCommandEncoder];
			[enc setLabel:[NSString stringWithFormat:@"%08x / %08x", dividend, divisor]];
			[enc setComputePipelineState:pipe];
			[enc setBuffer:data[0] offset:0 atIndex:0];
			[enc setBuffer:results[0] offset:0 atIndex:1];
			u32 constants[] = {dividend, divisor};
			[enc setBytes:constants length:sizeof(constants) atIndex:2];
			[enc dispatchThreadgroups:MTLSizeMake(count / 32, 1, 1) threadsPerThreadgroup:MTLSizeMake(32, 1, 1)];
			[enc endEncoding];
			[cb commit];
			[scope endScope];
			ok &= processLast();
			last = cb;
			std::swap(results[0], results[1]);
			std::swap(data[0], data[1]);
		}
		return ok;
	}

	bool finalize() {
		if (!dev)
			return false;
		@autoreleasepool {
			return processLast();
		}
	}
};

static bool parseDivisor(u32* out, const char* str) {
	char* end;
	unsigned long res = strtoul(str, &end, 16);
	if (end == str) {
		fprintf(stderr, "%s is not a hex number\n", str);
		return false;
	}
	if (res < 0x800000) {
		fprintf(stderr, "Divisor %lx is too small (must be at least 0x800000)\n", res);
		return false;
	}
	if (res > 0xffffff) {
		fprintf(stderr, "Divisor %lx is too large (must be at most 0xffffff)\n", res);
		return false;
	}
	*out = static_cast<u32>(res);
	return true;
}

static bool ishex(char c) {
	if (c >= '0' && c <= '9')
		return true;
	if (c >= 'a' && c <= 'f')
		return true;
	if (c >= 'A' && c <= 'F')
		return true;
	return false;
}

static bool parseDivisorFromFilename(u32* out, const char* str) {
	const char* end = str + strlen(str);
	u32 numhex = 0;
	while (end > str) {
		--end;
		if (ishex(*end)) {
			if (++numhex == 6 && parseDivisor(out, end))
				return true;
		} else {
			numhex = 0;
		}
	}
	return false;
}

static void expand(simd_uint4* buffer, const u32* src, size_t count, uint32_t dividend, uint32_t divisor) {
	int oldround = fegetround();
	fesetround(FE_TOWARDZERO);
	simd_uint4 vdividend = simd_uint4(dividend) + simd_make_uint4(0, 1, 2, 3);
	vdividend |= 0x3f800000;
	simd_uint4 vdivisor = simd_uint4(divisor | 0x3f800000);
	for (uint32_t i = 0; i < count; i++) {
		simd_uint4 elem = simd_uint4(src[i]);
		for (uint32_t j = 0; j < 32; j += 4, buffer++) {
			simd_uint4 bit = simd_make_uint4(1, 2, 4, 8) << j;
			simd_uint4 quotient = simd_uint4(simd_float4(vdividend) / simd_float4(vdivisor));
			quotient += ((elem & bit) != 0) ? 1 : 0;
			*buffer = quotient;
			vdividend += simd_uint4(4);
		}
	}
	fesetround(oldround);
}

int main(int argc, const char* argv[]) {
	if (argc <= 1) {
		fprintf(stderr, "Usage: %s operation file [file...]\n", argv[0]);
		return EXIT_FAILURE;
	}

	constexpr size_t maxtests = 0x800000 / 32;
	u32* buffer = static_cast<u32*>(malloc(sizeof(u32) * maxtests));
	MetalDivTest tester;
	u32 dividend = 0x800000;
	u32 divisor = 0x800000;
	bool startOverride = false;
	bool ok = true;

	for (int i = 1; i < argc; i++) {
		bool useStdin = 0 == strcmp(argv[i], "-");

		if (i + 1 < argc && 0 == strcasecmp(argv[i], "--start")) {
			if (parseDivisor(&divisor, argv[i + 1])) {
				i += 1;
				dividend = 0x800000;
				startOverride = true;
				continue;
			}
		}
		if (!startOverride) {
			if (parseDivisorFromFilename(&divisor, argv[i]))
				dividend = 0x800000;
		}

		FILE* file = useStdin ? stdin : fopen(argv[i], "r");
		if (!file) {
			fprintf(stderr, "Failed to open %s for reading: %s\n", argv[i], strerror(errno));
			continue;
		}
		while (true) {
			size_t ntests = fread(buffer, sizeof(u32), maxtests, file);
			if (ntests == 0) {
				int err = ferror(file);
				if (err) {
					fprintf(stderr, "Failed to read %s: %s\n", argv[i], strerror(err));
					ok = false;
				}
				break;
			}
			simd_uint4* gpubuf = static_cast<simd_uint4*>(tester.prepareNextBuffer(ntests * 32));
			expand(gpubuf, buffer, ntests, dividend, divisor);
			ok &= tester.process(ntests * 32, dividend | 0x3f800000, divisor | 0x3f800000);
			dividend += ntests * 32;
			if (dividend >= (1 << 24)) {
				dividend = 1 << 23;
				divisor += 1;
			}
		}
	}
	free(buffer);
}
