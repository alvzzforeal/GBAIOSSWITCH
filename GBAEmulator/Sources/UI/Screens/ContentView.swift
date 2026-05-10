// ContentView.swift
// Root view — routes between Library and Emulator screens.

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var emulatorState: EmulatorState
    @EnvironmentObject var romLibrary: ROMLibrary

    var body: some View {
        Group {
            switch emulatorState.status {
            case .idle:
                LibraryView()
            case .running, .paused:
                EmulatorView()
            case .error(let msg):
                ErrorView(message: msg)
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.25), value: isIdle)
    }

    private var isIdle: Bool {
        if case .idle = emulatorState.status { return true }
        return false
    }
}

struct ErrorView: View {
    let message: String
    @EnvironmentObject var emulatorState: EmulatorState

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.red)
            Text("Emulator Error")
                .font(.title.bold())
            Text(message)
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Back to Library") {
                emulatorState.stop()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
