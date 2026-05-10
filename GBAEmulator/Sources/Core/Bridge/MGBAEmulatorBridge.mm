// MGBAEmulatorBridge.mm
// Objective-C++ implementation connecting to the real mGBA C core.
//
// Dependencies (must be in project via mGBA source or static lib):
//   #include <mgba/core/core.h>
//   #include <mgba/core/serialize.h>
//   #include <mgba/gba/core.h>
//   #include <mgba/internal/gba/gba.h>
//   #include <mgba/internal/gba/input.h>
//   #include <mgba-util/memory.h>
//   #include <mgba-util/vfs.h>

#import "MGBAEmulatorBridge.h"

// --------------------------------------------------------------------------
// When mGBA headers are available, uncomment the block below and remove
// the #define STUB_MODE line.
// --------------------------------------------------------------------------

// #define MGBA_AVAILABLE   // <- uncomment when mGBA is in the project

#ifdef MGBA_AVAILABLE

#include <mgba/core/core.h>
#include <mgba/core/serialize.h>
#include <mgba/gba/core.h>
#include <mgba/internal/gba/gba.h>
#include <mgba/internal/gba/input.h>
#include <mgba-util/memory.h>
#include <mgba-util/vfs.h>
#include <blip_buf.h>

static const int GBA_WIDTH  = 240;
static const int GBA_HEIGHT = 160;
static const int SAMPLE_RATE = 32768;
static const int SAMPLES_PER_FRAME = SAMPLE_RATE / 60;

@implementation MGBAEmulatorBridge {
    struct mCore *_core;
    uint32_t _videoBuffer[GBA_WIDTH * GBA_HEIGHT];
    blip_t *_blipLeft;
    blip_t *_blipRight;
    int16_t _audioLeft[SAMPLES_PER_FRAME * 4];
    int16_t _audioRight[SAMPLES_PER_FRAME * 4];
    NSMutableData *_romStorage;
    uint32_t _keyState;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _core = GBACoreCreate();
        if (!_core) return nil;
        mCoreInitConfig(_core, NULL);

        struct mCoreOptions opts;
        memset(&opts, 0, sizeof(opts));
        opts.sampleRate = SAMPLE_RATE;
        opts.audioBuffers = SAMPLES_PER_FRAME * 2;
        mCoreConfigLoadDefaults(&_core->config, &opts);

        _core->init(_core);
        _core->setVideoBuffer(_core, _videoBuffer, GBA_WIDTH);

        _blipLeft  = blip_new(SAMPLE_RATE / 10);
        _blipRight = blip_new(SAMPLE_RATE / 10);
        _core->setAudioBufferSize(_core, SAMPLES_PER_FRAME * 2);

        _keyState = 0;
    }
    return self;
}

- (void)dealloc {
    if (_core) {
        _core->deinit(_core);
        _core = NULL;
    }
    if (_blipLeft)  blip_delete(_blipLeft);
    if (_blipRight) blip_delete(_blipRight);
}

- (BOOL)loadROM:(NSData *)romData {
    _romStorage = [romData mutableCopy];
    struct VFile *vf = VFileFromMemory(_romStorage.mutableBytes, _romStorage.length);
    if (!vf) return NO;
    BOOL ok = _core->loadROM(_core, vf);
    return ok;
}

- (void)start {
    _core->reset(_core);
}

- (void)pause { /* frame loop is stopped externally */ }
- (void)resume { /* frame loop is restarted externally */ }

- (void)reset {
    _core->reset(_core);
}

- (void)stepFrame {
    _core->setKeys(_core, _keyState);
    _core->runFrame(_core);
}

- (nullable NSData *)getVideoFrameBuffer {
    // Convert XBGR8888 to BGRA8888 (swap alpha)
    NSMutableData *out = [NSMutableData dataWithLength:GBA_WIDTH * GBA_HEIGHT * 4];
    uint32_t *src = _videoBuffer;
    uint8_t  *dst = (uint8_t *)out.mutableBytes;
    for (int i = 0; i < GBA_WIDTH * GBA_HEIGHT; i++) {
        uint32_t px = src[i];
        dst[i*4+0] = (px >>  0) & 0xFF; // B
        dst[i*4+1] = (px >>  8) & 0xFF; // G
        dst[i*4+2] = (px >> 16) & 0xFF; // R
        dst[i*4+3] = 0xFF;               // A
    }
    return out;
}

- (NSArray<NSNumber *> *)getAudioSamples {
    int available = (int)blip_samples_avail(_blipLeft);
    if (available <= 0) return @[];

    int count = MIN(available, SAMPLES_PER_FRAME * 2);
    blip_read_samples(_blipLeft,  _audioLeft,  count, 0);
    blip_read_samples(_blipRight, _audioRight, count, 0);

    NSMutableArray *out = [NSMutableArray arrayWithCapacity:count * 2];
    for (int i = 0; i < count; i++) {
        [out addObject:@(_audioLeft[i])];
        [out addObject:@(_audioRight[i])];
    }
    return out;
}

// GBA key bitmask matches GBAKey enum in mGBA (same order as our GBAButton Swift enum)
static const uint32_t kKeyMask[] = {
    GBA_KEY_A, GBA_KEY_B, GBA_KEY_SELECT, GBA_KEY_START,
    GBA_KEY_RIGHT, GBA_KEY_LEFT, GBA_KEY_UP, GBA_KEY_DOWN,
    GBA_KEY_R, GBA_KEY_L
};

- (void)pressButton:(NSInteger)buttonIndex {
    if (buttonIndex < 0 || buttonIndex > 9) return;
    _keyState |= kKeyMask[buttonIndex];
}

- (void)releaseButton:(NSInteger)buttonIndex {
    if (buttonIndex < 0 || buttonIndex > 9) return;
    _keyState &= ~kKeyMask[buttonIndex];
}

- (nullable NSData *)saveState {
    struct VFile *vf = VFileMemChunk(NULL, 0);
    if (!mCoreSaveStateNamed(_core, vf, SAVESTATE_ALL)) {
        vf->close(vf);
        return nil;
    }
    size_t size = vf->seek(vf, 0, SEEK_END);
    vf->seek(vf, 0, SEEK_SET);
    NSMutableData *data = [NSMutableData dataWithLength:size];
    vf->read(vf, data.mutableBytes, size);
    vf->close(vf);
    return data;
}

- (void)loadState:(NSData *)stateData {
    struct VFile *vf = VFileFromConstMemory(stateData.bytes, stateData.length);
    mCoreLoadStateNamed(_core, vf, SAVESTATE_ALL);
    vf->close(vf);
}

- (nullable NSData *)exportBatterySave {
    struct VFile *vf = VFileMemChunk(NULL, 0);
    _core->exportSave(_core, vf);
    size_t size = vf->seek(vf, 0, SEEK_END);
    if (size == 0) { vf->close(vf); return nil; }
    vf->seek(vf, 0, SEEK_SET);
    NSMutableData *data = [NSMutableData dataWithLength:size];
    vf->read(vf, data.mutableBytes, size);
    vf->close(vf);
    return data;
}

- (void)importBatterySave:(NSData *)saveData {
    struct VFile *vf = VFileFromConstMemory(saveData.bytes, saveData.length);
    _core->importSave(_core, vf);
    vf->close(vf);
}

@end

// --------------------------------------------------------------------------
#else // STUB MODE — compiles without mGBA, renders a test pattern
// --------------------------------------------------------------------------

static const int GBA_WIDTH  = 240;
static const int GBA_HEIGHT = 160;

@implementation MGBAEmulatorBridge {
    NSMutableData *_frameBuffer;
    uint32_t _frameCount;
    BOOL _loaded;
    uint32_t _keyState;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _frameBuffer = [NSMutableData dataWithLength:GBA_WIDTH * GBA_HEIGHT * 4];
        _frameCount = 0;
        _loaded = NO;
        _keyState = 0;
    }
    return self;
}

- (BOOL)loadROM:(NSData *)romData {
    // Validate minimum GBA ROM header size
    if (romData.length < 0xC0) return NO;
    _loaded = YES;
    return YES;
}

- (void)start  { _frameCount = 0; }
- (void)pause  {}
- (void)resume {}
- (void)reset  { _frameCount = 0; }

- (void)stepFrame {
    if (!_loaded) return;
    _frameCount++;

    // Generate animated test pattern (GBA rainbow bars + scanline effect)
    uint8_t *buf = (uint8_t *)_frameBuffer.mutableBytes;
    for (int y = 0; y < GBA_HEIGHT; y++) {
        for (int x = 0; x < GBA_WIDTH; x++) {
            int idx = (y * GBA_WIDTH + x) * 4;
            uint8_t r = (uint8_t)((x + _frameCount) % 256);
            uint8_t g = (uint8_t)((y * 2 + _frameCount / 2) % 256);
            uint8_t b = (uint8_t)((_frameCount * 2) % 256);
            // scanline dimming
            if (y % 2 == 0) { r = r * 3/4; g = g * 3/4; b = b * 3/4; }
            buf[idx+0] = b; // B
            buf[idx+1] = g; // G
            buf[idx+2] = r; // R
            buf[idx+3] = 0xFF;
        }
    }
}

- (nullable NSData *)getVideoFrameBuffer {
    if (!_loaded) return nil;
    return [_frameBuffer copy];
}

- (NSArray<NSNumber *> *)getAudioSamples {
    // Stub: generate a simple sine wave at 440 Hz for testing audio output
    const int count = 32768 / 60;
    NSMutableArray *samples = [NSMutableArray arrayWithCapacity:count * 2];
    double freq = 440.0;
    double sr = 32768.0;
    for (int i = 0; i < count; i++) {
        double t = (double)(_frameCount * count + i) / sr;
        int16_t s = (int16_t)(sin(2.0 * M_PI * freq * t) * 1000.0);
        [samples addObject:@(s)]; // L
        [samples addObject:@(s)]; // R
    }
    return samples;
}

- (void)pressButton:(NSInteger)buttonIndex {
    if (buttonIndex >= 0 && buttonIndex <= 9)
        _keyState |= (1u << buttonIndex);
}

- (void)releaseButton:(NSInteger)buttonIndex {
    if (buttonIndex >= 0 && buttonIndex <= 9)
        _keyState &= ~(1u << buttonIndex);
}

- (nullable NSData *)saveState {
    // Stub state = frameCount (4 bytes)
    NSMutableData *d = [NSMutableData dataWithLength:4];
    memcpy(d.mutableBytes, &_frameCount, 4);
    return d;
}

- (void)loadState:(NSData *)stateData {
    if (stateData.length >= 4)
        memcpy(&_frameCount, stateData.bytes, 4);
}

- (nullable NSData *)exportBatterySave {
    return nil; // stub has no save RAM
}

- (void)importBatterySave:(NSData *)saveData {
    // no-op in stub
}

@end

#endif
