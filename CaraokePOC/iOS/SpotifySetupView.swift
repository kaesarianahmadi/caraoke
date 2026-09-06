import SwiftUI

/// Dedicated Spotify connection sheet with full step-by-step developer dashboard instructions
public struct SpotifySetupView: View {
    @ObservedObject var spotifyAuth: SpotifyAuth
    var onConnected: (() -> Void)?

    @State private var clientIDText = SpotifyClientIDStore.stored ?? ""
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    public init(spotifyAuth: SpotifyAuth, onConnected: (() -> Void)? = nil) {
        self.spotifyAuth = spotifyAuth
        self.onConnected = onConnected
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background(scheme)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header info
                        HStack(spacing: 12) {
                            SpotifyLogo(size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Spotify Setup")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(AppTheme.fg(scheme))
                                Text(spotifyAuth.isConnected ? "Connected" : "Requires Spotify Developer App")
                                    .font(.system(size: 13))
                                    .foregroundColor(spotifyAuth.isConnected ? AppTheme.ok : AppTheme.muted(scheme))
                            }
                        }
                        .padding(.top, 10)

                        // Step by Step Instructions Card
                        VStack(alignment: .leading, spacing: 14) {
                            Text("How to connect your Spotify:")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(AppTheme.fg(scheme))

                            stepRow(number: "1", text: "Open developer.spotify.com/dashboard and log in.")
                            stepRow(number: "2", text: "Create an app named 'Caraoke' (Web API).")
                            stepRow(number: "3", text: "In App Settings, add Redirect URI:\ncaraoke://spotify-callback")
                            stepRow(number: "4", text: "Copy your Client ID and paste it below.")
                        }
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(AppTheme.surface(scheme)))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AppTheme.border(scheme), lineWidth: 1))

                        // Client ID Input Card
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Client ID")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppTheme.fg(scheme))

                            TextField("Paste Spotify Client ID", text: $clientIDText)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.system(size: 14).monospaced())
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(AppTheme.fg(scheme).opacity(0.06)))

                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.warn)
                            }

                            HStack(spacing: 12) {
                                Button {
                                    let trimmed = clientIDText.trimmingCharacters(in: .whitespacesAndNewlines)
                                    SpotifyClientIDStore.stored = trimmed
                                    isConnecting = true
                                    errorMessage = nil
                                    Task {
                                        do {
                                            try await spotifyAuth.connect()
                                            isConnecting = false
                                            onConnected?()
                                            dismiss()
                                        } catch {
                                            isConnecting = false
                                            errorMessage = error.localizedDescription
                                        }
                                    }
                                } label: {
                                    HStack {
                                        if isConnecting {
                                            ProgressView().tint(.white)
                                                .padding(.trailing, 4)
                                        }
                                        Text(spotifyAuth.isConnected ? "Reconnect" : "Save & Connect")
                                            .font(.system(size: 15, weight: .semibold))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color(hex: 0x1DB954))
                                    .foregroundColor(.black)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .disabled(clientIDText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isConnecting)

                                if spotifyAuth.isConnected {
                                    Button(role: .destructive) {
                                        spotifyAuth.disconnect()
                                        clientIDText = ""
                                        SpotifyClientIDStore.stored = nil
                                    } label: {
                                        Text("Disconnect")
                                            .font(.system(size: 15, weight: .medium))
                                            .padding(.vertical, 12)
                                            .padding(.horizontal, 16)
                                            .background(AppTheme.fg(scheme).opacity(0.08))
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                }
                            }
                        }
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(AppTheme.surface(scheme)))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AppTheme.border(scheme), lineWidth: 1))
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("Connect Spotify")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppTheme.fg(scheme))
                }
            }
        }
    }

    private func stepRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(Color(hex: 0x1DB954).opacity(0.2))
                Text(number)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(hex: 0x1DB954))
            }
            .frame(width: 22, height: 22)
            .padding(.top, 1)

            Text(text)
                .font(.system(size: 13))
                .foregroundColor(AppTheme.muted(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
