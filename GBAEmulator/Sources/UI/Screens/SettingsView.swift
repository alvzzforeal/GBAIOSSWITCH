// SettingsView.swift

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Audio") {
                    VStack(alignment: .leading) {
                        Text("Volume: \(Int(settingsStore.volume * 100))%")
                            .font(.subheadline)
                        Slider(value: $settingsStore.volume, in: 0...1)
                            .tint(Color(red: 0.6, green: 0.4, blue: 1.0))
                    }
                }

                Section("Video") {
                    Picker("Filter", selection: $settingsStore.videoFilter) {
                        ForEach(VideoFilterMode.allCases) { mode in
                            Text(mode.displayName).tag(mode.rawValue)
                        }
                    }

                    Toggle("Show FPS", isOn: $settingsStore.showFPS)
                }

                Section("Controls") {
                    VStack(alignment: .leading) {
                        Text("Button Opacity: \(Int(settingsStore.controllerOpacity * 100))%")
                            .font(.subheadline)
                        Slider(value: $settingsStore.controllerOpacity, in: 0.2...1.0)
                            .tint(Color(red: 0.6, green: 0.4, blue: 1.0))
                    }
                    Toggle("Haptic Feedback", isOn: $settingsStore.hapticFeedback)
                }

                Section("Saves") {
                    Toggle("Auto Save", isOn: $settingsStore.autoSave)

                    if settingsStore.autoSave {
                        VStack(alignment: .leading) {
                            Text("Interval: \(Int(settingsStore.autoSaveInterval))s")
                                .font(.subheadline)
                            Slider(value: $settingsStore.autoSaveInterval, in: 30...300, step: 30)
                                .tint(Color(red: 0.6, green: 0.4, blue: 1.0))
                        }
                    }
                }

                Section("About") {
                    LabeledContent("App Version", value: "1.0.0")
                    LabeledContent("Core", value: "mGBA (pending integration)")
                    LabeledContent("Compatibility", value: "iOS 17+")
                    Text("Use only ROMs you own legally. This app does not download or provide ROMs.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
