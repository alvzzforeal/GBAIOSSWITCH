#!/usr/bin/env python3
"""
Writes project.yml (xcodegen spec) and GBAEmulator/Info.plist.
Run from the repository root — same directory that contains the
GBAEmulator/ source folder.

Called by the GitHub Actions workflow step:
  run: python3 .github/scripts/write_project_files.py
"""

import os
import subprocess

# ── Resolve absolute paths to the mGBA install tree ──────────────────────────
root = subprocess.check_output(["pwd"]).decode().strip()
mgba_include = os.path.join(root, "mgba/build-ios/install/include")
mgba_lib     = os.path.join(root, "mgba/build-ios/install/lib")

# ── project.yml ───────────────────────────────────────────────────────────────
project_yml = f"""\
name: GBAEmulator
options:
  bundleIdPrefix: com.yourname
  deploymentTarget:
    iOS: "17.0"
  xcodeVersion: "15.4"
  createIntermediateGroups: true

settings:
  base:
    PRODUCT_NAME: GBAEmulator
    PRODUCT_BUNDLE_IDENTIFIER: com.yourname.gbaemulator
    SWIFT_VERSION: "5.9"
    ENABLE_BITCODE: NO
    OTHER_CPLUSPLUSFLAGS: "-std=c++17"
    SWIFT_OBJC_BRIDGING_HEADER: "GBAEmulator/GBAEmulator-Bridging-Header.h"
    OTHER_SWIFT_FLAGS: "-DMGBA_INTEGRATED"
    HEADER_SEARCH_PATHS: "{mgba_include}"
    LIBRARY_SEARCH_PATHS: "{mgba_lib}"
    OTHER_LDFLAGS: "-lmgba -lc++ -lz"
    CODE_SIGNING_ALLOWED: NO
    CODE_SIGNING_REQUIRED: NO

targets:
  GBAEmulator:
    type: application
    platform: iOS
    deploymentTarget: "17.0"
    sources:
      - path: GBAEmulator/Sources
        type: group
        createIntermediateGroups: true
      - path: GBAEmulator/GBAEmulator-Bridging-Header.h
    settings:
      base:
        INFOPLIST_FILE: GBAEmulator/Info.plist
    dependencies:
      - sdk: AVFoundation.framework
      - sdk: GameController.framework
      - sdk: MultipeerConnectivity.framework
"""

with open("project.yml", "w") as f:
    f.write(project_yml)
print("project.yml written")
print(project_yml)

# ── Info.plist ────────────────────────────────────────────────────────────────
os.makedirs("GBAEmulator", exist_ok=True)

info_plist = """\
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>GBAEmulator</string>
  <key>CFBundleIdentifier</key><string>com.yourname.gbaemulator</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>$(EXECUTABLE_NAME)</string>
  <key>LSRequiresIPhoneOS</key><true/>
  <key>UIFileSharingEnabled</key><true/>
  <key>LSSupportsOpeningDocumentsInPlace</key><true/>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>GBA ROM</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>CFBundleTypeExtensions</key>
      <array><string>gba</string></array>
      <key>LSItemContentTypes</key>
      <array><string>public.data</string></array>
    </dict>
  </array>
  <key>NSLocalNetworkUsageDescription</key>
  <string>GBA Emulator uses your local network for multiplayer link cable emulation.</string>
  <key>NSBonjourServices</key>
  <array>
    <string>_gba-link._tcp</string>
    <string>_gba-link._udp</string>
  </array>
  <key>UIBackgroundModes</key>
  <array><string>audio</string></array>
  <key>UIRequiredDeviceCapabilities</key>
  <array><string>arm64</string></array>
  <key>UISupportedInterfaceOrientations</key>
  <array>
    <string>UIInterfaceOrientationPortrait</string>
    <string>UIInterfaceOrientationLandscapeLeft</string>
    <string>UIInterfaceOrientationLandscapeRight</string>
  </array>
</dict>
</plist>
"""

with open("GBAEmulator/Info.plist", "w") as f:
    f.write(info_plist)
print("GBAEmulator/Info.plist written")
