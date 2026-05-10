// MGBAEmulatorBridge.h
// Objective-C++ interface wrapping the mGBA C API.
//
// COMPILE REQUIREMENTS:
//   1. Add mGBA source to your Xcode project (see INTEGRATION.md).
//   2. Add this file and MGBAEmulatorBridge.mm to your target.
//   3. Add a Bridging Header (GBAEmulator-Bridging-Header.h) that imports this file.
//   4. Set OTHER_CFLAGS to include mGBA's include path.
//
// HOW mGBA C API WORKS:
//   mGBA exposes a C API through:
//     - mgba/core/core.h      (mCoreCreate, mCoreLoadFile, etc.)
//     - mgba/gba/core.h       (GBACreate)
//     - mgba/core/blip_buf.h  (audio resampling)
//   We use GBA_VIDEO_VERTICAL_PIXELS (160) and GBA_VIDEO_HORIZONTAL_PIXELS (240).

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MGBAEmulatorBridge : NSObject

/// Load a GBA ROM from raw NSData. Returns YES if the ROM was accepted.
- (BOOL)loadROM:(NSData *)romData;

/// Start emulation from the beginning.
- (void)start;

/// Pause emulation.
- (void)pause;

/// Resume after pause.
- (void)resume;

/// Hard reset the emulator (like power cycling the GBA).
- (void)reset;

/// Advance exactly one video frame (~16.74ms). Runs the mCore's runFrame.
- (void)stepFrame;

/// Returns the current video frame as BGRA8888 Data (240*160*4 bytes), or nil.
- (nullable NSData *)getVideoFrameBuffer;

/// Returns interleaved stereo Int16 audio samples generated since last call.
- (NSArray<NSNumber *> *)getAudioSamples;

/// Map a button press (GBAButton raw value 0-9) to the mGBA key state.
- (void)pressButton:(NSInteger)buttonIndex;

/// Release a button.
- (void)releaseButton:(NSInteger)buttonIndex;

/// Serialize current emulator state to NSData for save states.
- (nullable NSData *)saveState;

/// Restore emulator state from NSData.
- (void)loadState:(NSData *)stateData;

/// Export battery-backed save (SRAM/Flash/EEPROM) as NSData.
- (nullable NSData *)exportBatterySave;

/// Import battery-backed save.
- (void)importBatterySave:(NSData *)saveData;

@end

NS_ASSUME_NONNULL_END
