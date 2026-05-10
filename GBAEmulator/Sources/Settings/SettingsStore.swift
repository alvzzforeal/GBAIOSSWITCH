// SettingsStore.swift
// Persistent user preferences using @AppStorage / UserDefaults.

import SwiftUI
import Combine

final class SettingsStore: ObservableObject {
    @AppStorage("volume") var volume: Double = 0.8
    @AppStorage("screenScale") var screenScale: Double = 1.0        // 1x, 1.5x, 2x, fit
    @AppStorage("videoFilter") var videoFilter: String = "nearest"  // nearest | bilinear | lcd
    @AppStorage("showFPS") var showFPS: Bool = true
    @AppStorage("autoSave") var autoSave: Bool = true
    @AppStorage("autoSaveInterval") var autoSaveInterval: Double = 60.0 // seconds
    @AppStorage("hapticFeedback") var hapticFeedback: Bool = true
    @AppStorage("controllerOpacity") var controllerOpacity: Double = 0.7
    @AppStorage("landscapeHideControls") var landscapeHideControls: Bool = false

    // Button mapping (gamepad) — stored as raw Int arrays
    @AppStorage("mfiButtonMap") private var mfiButtonMapData: Data = Data()

    var videoFilterMode: VideoFilterMode {
        VideoFilterMode(rawValue: videoFilter) ?? .nearest
    }
}

enum VideoFilterMode: String, CaseIterable, Identifiable {
    case nearest  = "nearest"
    case bilinear = "bilinear"
    case lcd      = "lcd"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nearest:  return "Pixel Perfect"
        case .bilinear: return "Smooth (Bilinear)"
        case .lcd:      return "LCD Grid"
        }
    }
}
