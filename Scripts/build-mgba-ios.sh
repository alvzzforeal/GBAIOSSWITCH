#!/usr/bin/env bash
# Scripts/build-mgba-ios.sh
#
# Compiles mGBA as a static library for iOS arm64 (device) using CMake's
# built-in Apple platform support (CMake ≥ 3.14 required, 3.20+ recommended).
#
# OUTPUT after a successful run:
#   ThirdParty/mgba/build-ios/install/include/   ← headers (already in git)
#   ThirdParty/mgba/build-ios/install/lib/libmgba.a
#
# PREREQUISITES on the build machine (macOS + Xcode):
#   brew install cmake ninja
#   xcode-select --install          # or full Xcode from App Store
#
# USAGE:
#   cd <repo-root>                  # directory that contains GBAEmulator/
#   bash Scripts/build-mgba-ios.sh
#
# Re-running is safe; it will reconfigure + rebuild if needed.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MGBA_SRC="${REPO_ROOT}/GBAEmulator/ThirdParty/mgba"
BUILD_DIR="${MGBA_SRC}/build-ios"
INSTALL_DIR="${BUILD_DIR}/install"

echo "══════════════════════════════════════════════════════════════"
echo " mGBA iOS build"
echo " Source  : ${MGBA_SRC}"
echo " Build   : ${BUILD_DIR}"
echo " Install : ${INSTALL_DIR}"
echo "══════════════════════════════════════════════════════════════"

# ── Sanity checks ─────────────────────────────────────────────────────────────

if ! command -v cmake &>/dev/null; then
    echo "ERROR: cmake not found. Install with: brew install cmake"
    exit 1
fi

if ! command -v ninja &>/dev/null; then
    echo "ERROR: ninja not found. Install with: brew install ninja"
    exit 1
fi

CMAKE_VER=$(cmake --version | head -1 | awk '{print $3}')
CMAKE_MAJOR=$(echo "${CMAKE_VER}" | cut -d. -f1)
CMAKE_MINOR=$(echo "${CMAKE_VER}" | cut -d. -f2)
if [[ "${CMAKE_MAJOR}" -lt 3 || ( "${CMAKE_MAJOR}" -eq 3 && "${CMAKE_MINOR}" -lt 14 ) ]]; then
    echo "ERROR: CMake ≥ 3.14 required (found ${CMAKE_VER})."
    exit 1
fi

if [[ ! -f "${MGBA_SRC}/CMakeLists.txt" ]]; then
    echo "ERROR: mGBA source not found at ${MGBA_SRC}"
    echo "       Run: git submodule update --init --recursive"
    exit 1
fi

# ── Detect latest iOS SDK ──────────────────────────────────────────────────────

IOS_SDK=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || true)
if [[ -z "${IOS_SDK}" ]]; then
    echo "ERROR: iOS SDK not found. Install Xcode and run 'xcode-select --install'."
    exit 1
fi
IOS_SDK_VER=$(xcrun --sdk iphoneos --show-sdk-version)
echo "iOS SDK: ${IOS_SDK} (${IOS_SDK_VER})"

# ── Configure ─────────────────────────────────────────────────────────────────

mkdir -p "${BUILD_DIR}"

cmake \
    -S "${MGBA_SRC}" \
    -B "${BUILD_DIR}" \
    -G Ninja \
    \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_ARCHITECTURES="arm64" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="14.0" \
    -DCMAKE_OSX_SYSROOT="${IOS_SDK}" \
    \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    \
    -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}" \
    \
    -DCMAKE_C_FLAGS="-fembed-bitcode-marker" \
    -DCMAKE_CXX_FLAGS="-fembed-bitcode-marker" \
    \
    -DUSE_FFMPEG=OFF \
    -DUSE_EPOXY=OFF \
    -DUSE_QT=OFF \
    -DUSE_SDL=OFF \
    -DUSE_EDITLINE=OFF \
    -DUSE_LIBZIP=OFF \
    -DUSE_ELF=OFF \
    -DUSE_LTO=OFF \
    -DENABLE_DEBUGGERS=OFF \
    -DENABLE_SCRIPTING=OFF \
    -DENABLE_LINK=OFF \
    -DBUILD_QT=OFF \
    -DBUILD_LIBRETRO=OFF \
    -DBUILD_CINEMA=OFF \
    -DBUILD_EXAMPLE=OFF \
    -DBUILD_TESTS=OFF \
    -DBUILD_PYTHON=OFF \
    \
    -DMINIMAL_CORE=OFF \
    -DENABLE_VFS=ON \
    -DENABLE_DIRECTORIES=ON

# ── Build ──────────────────────────────────────────────────────────────────────

CPU_COUNT=$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)
echo "Building with ${CPU_COUNT} parallel jobs…"
cmake --build "${BUILD_DIR}" -- -j"${CPU_COUNT}"

# ── Install ────────────────────────────────────────────────────────────────────

cmake --install "${BUILD_DIR}"

# ── Verify ────────────────────────────────────────────────────────────────────

LIB="${INSTALL_DIR}/lib/libmgba.a"
if [[ ! -f "${LIB}" ]]; then
    # mGBA sometimes installs as mgba or mgba-static depending on CMake version.
    LIB_ALT=$(find "${INSTALL_DIR}/lib" -name "*.a" | head -1)
    if [[ -n "${LIB_ALT}" ]]; then
        cp "${LIB_ALT}" "${INSTALL_DIR}/lib/libmgba.a"
        LIB="${INSTALL_DIR}/lib/libmgba.a"
    fi
fi

if [[ -f "${LIB}" ]]; then
    ARCH=$(lipo -info "${LIB}" 2>/dev/null || file "${LIB}")
    echo ""
    echo "✓ Build successful!"
    echo "  Library : ${LIB}"
    echo "  Arch    : ${ARCH}"
    echo ""
    echo "Next steps in Xcode:"
    echo "  1. In MGBAEmulatorBridge.mm: uncomment  #define MGBA_AVAILABLE"
    echo "  2. Build Settings:"
    echo "     Header Search Paths  → \$(SRCROOT)/GBAEmulator/ThirdParty/mgba/include"
    echo "                            \$(SRCROOT)/GBAEmulator/ThirdParty/mgba/build-ios/install/include"
    echo "     Library Search Paths → \$(SRCROOT)/GBAEmulator/ThirdParty/mgba/build-ios/install/lib"
    echo "     Other Linker Flags   → -lmgba -lc++ -lz"
    echo "     Other Swift Flags    → -DMGBA_INTEGRATED"
    echo "     Obj-C Bridging Header→ GBAEmulator/GBAEmulator-Bridging-Header.h"
    echo "  3. Add MGBAEmulatorBridge.mm to Compile Sources in Build Phases."
    echo "  4. Clean & Build."
else
    echo ""
    echo "ERROR: libmgba.a not found in ${INSTALL_DIR}/lib"
    echo "Contents of install/lib:"
    ls "${INSTALL_DIR}/lib/" 2>/dev/null || echo "  (directory missing)"
    exit 1
fi
