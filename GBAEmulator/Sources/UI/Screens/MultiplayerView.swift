// MultiplayerView.swift
// Local Wi-Fi multiplayer session management UI.

import SwiftUI

struct MultiplayerView: View {
    @EnvironmentObject var multiplayerService: LocalMultiplayerService
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        statusCard
                        sessionControls
                        peerList
                        logSection
                        limitationsNote
                    }
                    .padding()
                }
            }
            .navigationTitle("Local Multiplayer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.white)
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Status Card

    private var statusCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.2))
                    .frame(width: 56, height: 56)
                Image(systemName: statusIcon)
                    .font(.title2)
                    .foregroundColor(statusColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(statusLabel)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(statusDetail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(Color(white: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Session Controls

    private var sessionControls: some View {
        VStack(spacing: 12) {
            Text("Start a Session")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                sessionButton(
                    label: "Host Game",
                    subtitle: "Create a session",
                    icon: "antenna.radiowaves.left.and.right",
                    color: Color(red: 0.6, green: 0.4, blue: 1.0)
                ) {
                    multiplayerService.startHosting()
                }

                sessionButton(
                    label: "Join Game",
                    subtitle: "Find a host",
                    icon: "magnifyingglass.circle.fill",
                    color: Color(red: 0.2, green: 0.7, blue: 0.5)
                ) {
                    multiplayerService.startBrowsing()
                }
            }

            if case .advertising = multiplayerService.state {
                disconnectButton
            } else if case .browsing = multiplayerService.state {
                disconnectButton
            } else if case .connected = multiplayerService.state {
                disconnectButton
            }
        }
    }

    @ViewBuilder
    private func sessionButton(label: String, subtitle: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundColor(color)
                VStack(spacing: 2) {
                    Text(label)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(color.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(color.opacity(0.3), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var disconnectButton: some View {
        Button(action: { multiplayerService.disconnect() }) {
            Label("Disconnect", systemImage: "xmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.red.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Peer List

    @ViewBuilder
    private var peerList: some View {
        if !multiplayerService.discoveredPeers.isEmpty || !multiplayerService.connectedPeers.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Devices")
                    .font(.subheadline.bold())
                    .foregroundColor(.secondary)

                // Discovered (browsing)
                ForEach(multiplayerService.discoveredPeers) { peer in
                    peerRow(name: peer.displayName, status: "Available", color: .blue) {
                        multiplayerService.connect(to: peer)
                    }
                }

                // Connected
                ForEach(multiplayerService.connectedPeers) { peer in
                    peerRow(name: peer.displayName, status: "Connected ✓", color: .green, action: nil)
                }
            }
            .padding()
            .background(Color(white: 0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    @ViewBuilder
    private func peerRow(name: String, status: String, color: Color, action: (() -> Void)?) -> some View {
        HStack {
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "iphone")
                        .font(.system(size: 14))
                        .foregroundColor(color)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text(status)
                    .font(.caption)
                    .foregroundColor(color)
            }
            Spacer()
            if let action = action {
                Button("Connect", action: action)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.6, green: 0.4, blue: 1.0))
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Log

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Session Log")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(multiplayerService.sessionLog.reversed(), id: \.self) { line in
                        Text(line)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.green.opacity(0.8))
                    }
                }
            }
            .frame(height: 120)
            .padding(10)
            .background(Color.black.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding()
        .background(Color(white: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Limitations Note

    private var limitationsNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Technical Notes", systemImage: "info.circle")
                .font(.caption.bold())
                .foregroundColor(.yellow)

            Text("""
            • GBA link cable runs at 256Kbps–2Mbps. Wi-Fi adds ~1-frame latency.
            • Most turn-based games (Pokémon trading) work well.
            • Fast action games (F-Zero GP Legend battle) may feel delayed.
            • Both players must be on the same Wi-Fi network.
            • Up to 4 players supported (like GBA Multiplayer Mode).
            • Link cable emulation requires mGBA core integration.
            """)
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.yellow.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.yellow.opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Status Helpers

    private var statusColor: Color {
        switch multiplayerService.state {
        case .idle: return .gray
        case .advertising: return .orange
        case .browsing: return .blue
        case .connecting: return .yellow
        case .connected: return .green
        case .failed: return .red
        }
    }

    private var statusIcon: String {
        switch multiplayerService.state {
        case .idle: return "wifi.slash"
        case .advertising: return "antenna.radiowaves.left.and.right"
        case .browsing: return "magnifyingglass"
        case .connecting: return "clock.fill"
        case .connected: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var statusLabel: String {
        switch multiplayerService.state {
        case .idle: return "Not Connected"
        case .advertising: return "Hosting Session"
        case .browsing: return "Searching for Hosts..."
        case .connecting(let p): return "Connecting to \(p.displayName)"
        case .connected: return "Connected (\(multiplayerService.connectedPeers.count + 1) players)"
        case .failed(let e): return "Error: \(e)"
        }
    }

    private var statusDetail: String {
        switch multiplayerService.state {
        case .idle: return "Start a session or join an existing one"
        case .advertising: return "Waiting for players to join..."
        case .browsing: return "Make sure both devices are on the same Wi-Fi"
        case .connecting: return "Establishing connection..."
        case .connected: return "Link cable emulation active"
        case .failed: return "Check Wi-Fi connection and try again"
        }
    }
}
