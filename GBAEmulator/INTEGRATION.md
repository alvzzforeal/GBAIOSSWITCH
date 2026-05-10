# INTEGRATION.md
# GBA Emulator — Complete Xcode Integration Guide

## 1. Project Setup

### Create the Xcode Project
1. Xcode → File → New → Project
2. Choose **App** (iOS, SwiftUI interface, Swift language)
3. Name: `GBAEmulator`
4. Bundle ID: `com.yourname.gbaemulator`
5. Minimum Deployment: **iOS 17.0**

### Add All Source Files
Copy all `.swift` files from `Sources/` into the project target.
Copy `MGBAEmulatorBridge.h` and `MGBAEmulatorBridge.mm` into the project.
Set `GBAEmulator-Bridging-Header.h` in Build Settings.

---

## 2. Bridging Header Setup

1. In Xcode, select your target → **Build Settings**
2. Search for `Objective-C Bridging Header`
3. Set value to: `GBAEmulator/GBAEmulator-Bridging-Header.h`
4. Ensure `MGBAEmulatorBridge.h` and `.mm` are in the target's **Compile Sources**

---

## 3. Integrating mGBA Core

mGBA is open source (MPL-2.0): https://github.com/mgba-emu/mgba

### Step A: Get mGBA Source
```bash
git clone https://github.com/mgba-emu/mgba.git
cd mgba
git checkout 0.10.3  # Latest stable tag
```

### Step B: Build for iOS (ARM64)
mGBA uses CMake. Build a static library for iOS:

```bash
mkdir build-ios && cd build-ios

cmake .. \
  -DCMAKE_TOOLCHAIN_FILE=../cmake/Toolchain-ios.cmake \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED=OFF \
  -DBUILD_STATIC=ON \
  -DUSE_FFMPEG=OFF \
  -DUSE_MAGICK=OFF \
  -DUSE_MINIZIP=OFF \
  -DUSE_EPOXY=OFF \
  -DUSE_LIBZIP=OFF \
  -DENABLE_DEBUGGERS=OFF \
  -DENABLE_SCRIPTING=OFF \
  -DENABLE_GBA=ON \
  -DENABLE_GB=OFF \
  -DENABLE_GBP=OFF \
  -DENABLE_NDS=OFF \
  -DCMAKE_OSX_SYSROOT=$(xcrun --sdk iphoneos --show-sdk-path) \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_INSTALL_PREFIX=./install

cmake --build . --config Release --target install -j$(sysctl -n hw.ncpu)
```

The iOS toolchain file (`cmake/Toolchain-ios.cmake`) is included in the mGBA repo.

### Step C: Add to Xcode Project
1. Drag `install/lib/libmgba.a` into your Xcode project → Add to target
2. Drag `install/include/` folder → Add to project (reference, not copy)
3. In **Build Settings** → **Header Search Paths**, add the include path:
   `$(PROJECT_DIR)/mgba/build-ios/install/include`
4. In **Build Settings** → **Other Linker Flags**, add:
   `-lmgba -lc++`
5. Link frameworks: **AVFoundation**, **GameController**, **MultipeerConnectivity**

### Step D: Enable mGBA in Bridge
In `MGBAEmulatorBridge.mm`, uncomment:
```objc
#define MGBA_AVAILABLE
```

In `EmulatorCore.swift`, add to **Build Settings** → **Other Swift Flags**:
```
-DMGBA_INTEGRATED
```

---

## 4. Info.plist Required Entries

Add these keys to your `Info.plist`:

```xml
<!-- File access -->
<key>UIFileSharingEnabled</key>
<true/>
<key>LSSupportsOpeningDocumentsInPlace</key>
<true/>
<key>CFBundleDocumentTypes</key>
<array>
    <dict>
        <key>CFBundleTypeName</key>
        <string>GBA ROM</string>
        <key>CFBundleTypeRole</key>
        <string>Viewer</string>
        <key>LSItemContentTypes</key>
        <array>
            <string>public.data</string>
        </array>
        <key>CFBundleTypeExtensions</key>
        <array>
            <string>gba</string>
        </array>
    </dict>
</array>
<key>UTExportedTypeDeclarations</key>
<array>
    <dict>
        <key>UTTypeIdentifier</key>
        <string>com.yourname.gba-rom</string>
        <key>UTTypeDescription</key>
        <string>GBA ROM File</string>
        <key>UTTypeConformsTo</key>
        <array><string>public.data</string></array>
        <key>UTTypeTagSpecification</key>
        <dict>
            <key>public.filename-extension</key>
            <array><string>gba</string></array>
        </dict>
    </dict>
</array>

<!-- Local network (MultipeerConnectivity) -->
<key>NSLocalNetworkUsageDescription</key>
<string>GBA Emulator uses your local network to connect with nearby players for multiplayer link cable emulation.</string>
<key>NSBonjourServices</key>
<array>
    <string>_gba-link._tcp</string>
    <string>_gba-link._udp</string>
</array>

<!-- Microphone not needed; keep audio background mode if desired -->
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>

<!-- Required device capabilities -->
<key>UIRequiredDeviceCapabilities</key>
<array>
    <string>arm64</string>
</array>

<!-- Orientation support -->
<key>UISupportedInterfaceOrientations</key>
<array>
    <string>UIInterfaceOrientationPortrait</string>
    <string>UIInterfaceOrientationLandscapeLeft</string>
    <string>UIInterfaceOrientationLandscapeRight</string>
</array>
```

---

## 5. Build Settings Summary

| Setting | Value |
|---|---|
| iOS Deployment Target | 17.0 |
| Swift Language Version | 5.9+ |
| Objective-C Bridging Header | GBAEmulator/GBAEmulator-Bridging-Header.h |
| Other Swift Flags | `-DMGBA_INTEGRATED` (after mGBA integration) |
| Other C++ Flags | `-std=c++17` |
| Header Search Paths | `$(PROJECT_DIR)/mgba/build-ios/install/include` |
| Library Search Paths | `$(PROJECT_DIR)/mgba/build-ios/install/lib` |
| Other Linker Flags | `-lmgba -lc++ -lz` |
| Enable Bitcode | No (mGBA doesn't support it) |

---

## 6. Testing Multiplayer on Two iPhones

### Prerequisites
- Both iPhones on the same Wi-Fi network (or using iPhone hotspot)
- Two copies of the app installed (use TestFlight or Xcode with 2 provisioning profiles)
- Same game ROM on both devices

### Steps
1. **Device A (Host):** Open app → Wi-Fi icon → "Host Game"
2. **Device B (Client):** Open app → Wi-Fi icon → "Join Game" → select Device A → "Connect"
3. Both load the same ROM and start playing
4. The LinkCableManager will sync SIO data each frame

### Troubleshooting
- If discovery fails: disable VPN, check router doesn't block peer-to-peer
- MultipeerConnectivity also works over Bluetooth as fallback
- Check Console.app for `[LocalMultiplayerService]` log lines

---

## 7. What is 100% Functional (Stub mode)

✅ ROM import from Files app  
✅ ROM library with persistence  
✅ Animated test pattern rendering (proves video pipeline works)  
✅ Audio sine wave output (proves audio pipeline works)  
✅ Virtual D-pad, A/B/L/R/Start/Select buttons with haptics  
✅ MFi/Bluetooth controller support  
✅ Save states (structure + serialization)  
✅ Battery save import/export (structure)  
✅ MultipeerConnectivity discovery + session  
✅ Link packet serialization/deserialization  
✅ LinkCableManager frame sync protocol  
✅ Pause menu with save/load slot UI  
✅ Settings persistence  
✅ Portrait + landscape layouts  

## 8. What Requires mGBA Integration

⚠️ Actual GBA game execution (CPU/GPU/APU emulation)  
⚠️ Real video frames from game  
⚠️ Real audio from game  
⚠️ Real save states from game memory  
⚠️ Real battery save (SRAM/Flash/EEPROM)  
⚠️ Link cable SIO register hooking (mGBA has internal LinkRaw support)  

All the infrastructure (Swift classes, ObjC++ bridge, UI, network) is complete.
Plugging in mGBA replaces `StubEmulatorBridge` with real `MGBAEmulatorBridge` — no architectural changes needed.

---

## 9. Legal Notes

- mGBA is open source under MPL-2.0. You must comply with its license if distributing.
- Do NOT include GBA BIOS (`gba_bios.bin`). mGBA has a built-in open-source HLE BIOS.
- Do NOT include any ROM files.
- App Store distribution of emulators is permitted as of April 2024 (Apple policy change).
  However, compliance review may still apply. Consult Apple's guidelines before submitting.
