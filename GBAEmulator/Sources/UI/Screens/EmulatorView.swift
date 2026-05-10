// EmulatorView.swift
// Full emulator screen: video output + virtual GBA controls.

import SwiftUI
import GameController

struct EmulatorView: View {
    @EnvironmentObject var emulatorState: EmulatorState
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.horizontalSizeClass) var hSizeClass

    @State private var showPauseMenu = false
    @StateObject private var gcController = GameControllerManager()

    var isLandscape: Bool {
        UIDevice.current.orientation.isLandscape
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Group {
                if isLandscape {
                    landscapeLayout
                } else {
                    portraitLayout
                }
            }

            // FPS overlay
            if settingsStore.showFPS {
                VStack {
                    HStack {
                        Spacer()
                        Text(String(format: "%.0f FPS", emulatorState.fps))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.green.opacity(0.8))
                            .padding(4)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(4)
                            .padding(.top, 50)
                            .padding(.trailing, 8)
                    }
                    Spacer()
                }
            }

            // Pause menu overlay
            if emulatorState.showPauseMenu {
                PauseMenuView()
                    .transition(.opacity)
            }
        }
        .onReceive(gcController.$buttonPressed) { button in
            if let button = button { emulatorState.press(button: button) }
        }
        .onReceive(gcController.$buttonReleased) { button in
            if let button = button { emulatorState.release(button: button) }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }

    // MARK: - Portrait

    private var portraitLayout: some View {
        VStack(spacing: 0) {
            Spacer()
            GBAScreenView()
                .aspectRatio(1.5, contentMode: .fit)
                .padding(.horizontal, 8)
            Spacer(minLength: 8)
            VirtualControllerView()
                .padding(.horizontal, 4)
                .padding(.bottom, 20)
        }
    }

    // MARK: - Landscape

    private var landscapeLayout: some View {
        HStack(spacing: 0) {
            // Left controls (D-pad + Select/Start)
            VStack {
                Spacer()
                DPadView()
                Spacer()
                HStack(spacing: 24) {
                    StartSelectView()
                }
                .padding(.bottom, 16)
            }
            .frame(width: 160)

            // Screen
            GBAScreenView()
                .aspectRatio(1.5, contentMode: .fit)
                .padding(.vertical, 8)

            // Right controls (A/B + L/R + pause)
            VStack {
                Spacer()
                FaceButtonsView()
                Spacer()
                HStack(spacing: 16) {
                    ShoulderButtonsView()
                }
                .padding(.bottom, 16)
            }
            .frame(width: 160)
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - GBA Screen

struct GBAScreenView: View {
    @EnvironmentObject var emulatorState: EmulatorState
    @EnvironmentObject var settingsStore: SettingsStore

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Bezel
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(white: 0.05))

                // Game image
                if let frame = emulatorState.currentFrame {
                    Image(frame, scale: 1, label: Text("Game Screen"))
                        .resizable()
                        .interpolation(interpolationMode)
                        .aspectRatio(contentMode: .fit)
                        .overlay(lcdOverlay)
                } else {
                    // Splash / loading
                    VStack(spacing: 12) {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.white.opacity(0.2))
                        Text(emulatorState.currentROM?.title ?? "Loading...")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.3))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .onTapGesture(count: 2) {
            // Double-tap to pause
            if case .running = emulatorState.status {
                emulatorState.pause()
            }
        }
    }

    private var interpolationMode: Image.Interpolation {
        switch settingsStore.videoFilterMode {
        case .nearest: return .none
        case .bilinear: return .medium
        case .lcd: return .none
        }
    }

    @ViewBuilder
    private var lcdOverlay: some View {
        if settingsStore.videoFilterMode == .lcd {
            LCDGridOverlay()
        } else {
            EmptyView()
        }
    }
}

// MARK: - LCD Grid Overlay

struct LCDGridOverlay: View {
    var body: some View {
        Canvas { context, size in
            let cellW: CGFloat = size.width / 240
            let cellH: CGFloat = size.height / 160
            for x in stride(from: 0.0, through: size.width, by: cellW) {
                let p = Path { path in path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)) }
                context.stroke(p, with: .color(.black.opacity(0.15)), lineWidth: 0.5)
            }
            for y in stride(from: 0.0, through: size.height, by: cellH) {
                let p = Path { path in path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)) }
                context.stroke(p, with: .color(.black.opacity(0.15)), lineWidth: 0.5)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Full Virtual Controller (portrait)

struct VirtualControllerView: View {
    @EnvironmentObject var settingsStore: SettingsStore

    var body: some View {
        VStack(spacing: 0) {
            // Shoulder buttons
            HStack {
                ShoulderButtonView(button: .l, label: "L")
                Spacer()
                ShoulderButtonView(button: .r, label: "R")
            }
            .padding(.horizontal, 8)

            HStack(alignment: .center, spacing: 0) {
                // D-pad
                DPadView()
                    .frame(width: 140, height: 140)

                Spacer()

                // Start/Select
                VStack(spacing: 16) {
                    StartSelectView()
                }

                Spacer()

                // A/B
                FaceButtonsView()
                    .frame(width: 120, height: 120)
            }
            .padding(.horizontal, 8)
        }
        .opacity(settingsStore.controllerOpacity)
    }
}

// MARK: - D-Pad

struct DPadView: View {
    @EnvironmentObject var emulatorState: EmulatorState

    var body: some View {
        ZStack {
            // Center
            Circle()
                .fill(Color(white: 0.18))
                .frame(width: 44, height: 44)

            // Cross arms
            VStack(spacing: 0) {
                dpadButton(.up, systemImage: "chevron.up")
                Spacer()
                dpadButton(.down, systemImage: "chevron.down")
            }

            HStack(spacing: 0) {
                dpadButton(.left, systemImage: "chevron.left")
                Spacer()
                dpadButton(.right, systemImage: "chevron.right")
            }
        }
        .frame(width: 130, height: 130)
    }

    @ViewBuilder
    private func dpadButton(_ button: GBAButton, systemImage: String) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color(white: 0.18))
            .frame(width: 42, height: 42)
            .overlay(
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
            )
            .pressAction(
                onPress: { emulatorState.press(button: button) },
                onRelease: { emulatorState.release(button: button) }
            )
    }
}

// MARK: - Face Buttons (A / B)

struct FaceButtonsView: View {
    @EnvironmentObject var emulatorState: EmulatorState

    var body: some View {
        ZStack {
            faceButton(.a, label: "A", color: Color(red: 0.9, green: 0.1, blue: 0.1), offset: CGPoint(x: 36, y: 0))
            faceButton(.b, label: "B", color: Color(red: 0.1, green: 0.5, blue: 0.9), offset: CGPoint(x: 0, y: 36))
        }
        .frame(width: 100, height: 100)
    }

    @ViewBuilder
    private func faceButton(_ button: GBAButton, label: String, color: Color, offset: CGPoint) -> some View {
        Circle()
            .fill(color)
            .frame(width: 44, height: 44)
            .overlay(
                Text(label)
                    .font(.system(size: 16, weight: .black))
                    .foregroundColor(.white)
            )
            .offset(x: offset.x, y: offset.y)
            .pressAction(
                onPress: { emulatorState.press(button: button) },
                onRelease: { emulatorState.release(button: button) }
            )
    }
}

// MARK: - Start / Select

struct StartSelectView: View {
    @EnvironmentObject var emulatorState: EmulatorState

    var body: some View {
        HStack(spacing: 12) {
            pillButton(.select, label: "SELECT")
            pillButton(.start, label: "START")
        }
    }

    @ViewBuilder
    private func pillButton(_ button: GBAButton, label: String) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundColor(.white.opacity(0.8))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(white: 0.22))
            .clipShape(Capsule())
            .pressAction(
                onPress: { emulatorState.press(button: button) },
                onRelease: { emulatorState.release(button: button) }
            )
    }
}

// MARK: - Shoulder Buttons

struct ShoulderButtonsView: View {
    @EnvironmentObject var emulatorState: EmulatorState
    var body: some View {
        HStack(spacing: 80) {
            ShoulderButtonView(button: .l, label: "L")
            ShoulderButtonView(button: .r, label: "R")
        }
    }
}

struct ShoulderButtonView: View {
    @EnvironmentObject var emulatorState: EmulatorState
    let button: GBAButton
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 60, height: 28)
            .background(Color(white: 0.22))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .pressAction(
                onPress: { emulatorState.press(button: button) },
                onRelease: { emulatorState.release(button: button) }
            )
    }
}

// MARK: - Press Action Modifier

struct PressActionModifier: ViewModifier {
    let onPress: () -> Void
    let onRelease: () -> Void
    @State private var isPressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.88 : 1.0)
            .animation(.easeInOut(duration: 0.08), value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            onPress()
                            let haptic = UIImpactFeedbackGenerator(style: .light)
                            haptic.impactOccurred()
                        }
                    }
                    .onEnded { _ in
                        isPressed = false
                        onRelease()
                    }
            )
    }
}

extension View {
    func pressAction(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) -> some View {
        modifier(PressActionModifier(onPress: onPress, onRelease: onRelease))
    }
}

// MARK: - MFi/Bluetooth GameController Manager

@MainActor
final class GameControllerManager: ObservableObject {
    @Published var buttonPressed: GBAButton?
    @Published var buttonReleased: GBAButton?
    @Published var isConnected = false

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerConnected),
            name: .GCControllerDidConnect,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerDisconnected),
            name: .GCControllerDidDisconnect,
            object: nil
        )
        GCController.startWirelessControllerDiscovery()
        if let controller = GCController.controllers().first {
            setupController(controller)
        }
    }

    @objc private func controllerConnected(_ notification: Notification) {
        guard let controller = notification.object as? GCController else { return }
        isConnected = true
        setupController(controller)
    }

    @objc private func controllerDisconnected(_ notification: Notification) {
        isConnected = false
    }

    private func setupController(_ controller: GCController) {
        guard let gamepad = controller.extendedGamepad else { return }

        gamepad.buttonA.valueChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in pressed ? (self?.buttonPressed = .a) : (self?.buttonReleased = .a) }
        }
        gamepad.buttonB.valueChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in pressed ? (self?.buttonPressed = .b) : (self?.buttonReleased = .b) }
        }
        gamepad.leftShoulder.valueChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in pressed ? (self?.buttonPressed = .l) : (self?.buttonReleased = .l) }
        }
        gamepad.rightShoulder.valueChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in pressed ? (self?.buttonPressed = .r) : (self?.buttonReleased = .r) }
        }
        gamepad.buttonMenu.valueChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in pressed ? (self?.buttonPressed = .start) : (self?.buttonReleased = .start) }
        }
        gamepad.buttonOptions?.valueChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in pressed ? (self?.buttonPressed = .select) : (self?.buttonReleased = .select) }
        }
        gamepad.dpad.valueChangedHandler = { [weak self] _, xAxis, yAxis in
            Task { @MainActor in
                self?.handleDpad(x: xAxis, y: yAxis)
            }
        }
    }

    private var dpadState: Set<GBAButton> = []

    private func handleDpad(x: Float, y: Float) {
        let newState: Set<GBAButton> = {
            var s = Set<GBAButton>()
            if x > 0.5 { s.insert(.right) } else if x < -0.5 { s.insert(.left) }
            if y > 0.5 { s.insert(.up) }    else if y < -0.5 { s.insert(.down) }
            return s
        }()

        for b in newState.subtracting(dpadState) { buttonPressed = b }
        for b in dpadState.subtracting(newState) { buttonReleased = b }
        dpadState = newState
    }
}
