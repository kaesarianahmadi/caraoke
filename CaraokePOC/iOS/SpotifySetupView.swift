import SwiftUI
import UIKit

/// Frictionless Spotify setup: 1-tap bundled OAuth + progressive disclosure for custom Client ID + canonical redirect URI copy.
struct SpotifySetupView: View {
    @ObservedObject var spotifyAuth: SpotifyAuth
    var onConnected: (() -> Void)?

    @State private var clientIDText = SpotifyClientIDStore.stored ?? ""
    @State private var showCustomID = !(SpotifyClientIDStore.stored ?? "").isEmpty
    @State private var isConnecting = false
    @State private var copiedURI = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    init(spotifyAuth: SpotifyAuth, onConnected: (() -> Void)? = nil) {
        self.spotifyAuth = spotifyAuth
        self.onConnected = onConnected
    }

    private var trimmedClientID: String {
        clientIDText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canConnect: Bool {
        !isConnecting && (spotifyAuth.hasClientID || !trimmedClientID.isEmpty)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.bg(scheme).ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 12) {
                            SpotifyLogo(size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Spotify Setup")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(AppTheme.fg(scheme))
                                Text(spotifyAuth.isConnected ? "Connected" : "1-tap sign-in or custom Client ID")
                                    .font(.system(size: 13))
                                    .foregroundColor(spotifyAuth.isConnected ? AppTheme.ok : AppTheme.muted(scheme))
                            }
                        }
                        .padding(.top, 10)

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AppTheme.warn)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppTheme.warn.opacity(0.12)))
                        }

                        // Primary 1-tap OAuth CTA (uses bundled Client ID if custom is empty)
                        HStack(spacing: 12) {
                            Button {
                                startConnect(savingCustomID: false)
                            } label: {
                                HStack {
                                    if isConnecting {
                                        ProgressView().tint(.black).padding(.trailing, 4)
                                    }
                                    Text(spotifyAuth.isConnected ? "Reconnect Spotify" : "Connect with Spotify")
                                        .font(.system(size: 15, weight: .bold))
                                }
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 48)
                                .background(Color(hex: 0x1DB954))
                                .foregroundColor(.black)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .disabled(!canConnect)

                            if spotifyAuth.isConnected {
                                Button(role: .destructive) {
                                    spotifyAuth.disconnect()
                                    clientIDText = ""
                                    SpotifyClientIDStore.stored = nil
                                } label: {
                                    Text("Disconnect")
                                        .font(.system(size: 15, weight: .semibold))
                                        .frame(minHeight: 48)
                                        .padding(.horizontal, 16)
                                        .background(AppTheme.surface(scheme))
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppTheme.border(scheme), lineWidth: 1))
                                }
                            }
                        }

                        // Progressive Disclosure for BYO Client ID (403 beta limit bypass)
                        DisclosureGroup(
                            isExpanded: $showCustomID,
                            content: {
                                VStack(alignment: .leading, spacing: 14) {
                                    stepRow(number: "1", text: "Open developer.spotify.com/dashboard and log in.")
                                    stepRow(number: "2", text: "Create an app named 'Caraoke' (Web API).")
                                    stepRow(number: "3", text: "Under Redirect URIs, add exactly:\n\(SpotifyAuth.redirectURI)")

                                    Button {
                                        UIPasteboard.general.string = SpotifyAuth.redirectURI
                                        copiedURI = true
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                            copiedURI = false
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: copiedURI ? "checkmark.circle.fill" : "doc.on.doc")
                                            Text(copiedURI ? "Copied \(SpotifyAuth.redirectURI)" : "Copy \(SpotifyAuth.redirectURI)")
                                                .font(.caption.weight(.bold).monospaced())
                                        }
                                        .foregroundColor(copiedURI ? AppTheme.ok : AppTheme.fg(scheme))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Capsule().fill(AppTheme.surfaceElevated(scheme)))
                                    }
                                    .buttonStyle(.plain)

                                    stepRow(number: "4", text: "Copy your Client ID and paste it below.")

                                    TextField("Paste Spotify Client ID", text: $clientIDText)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .font(.system(size: 14).monospaced())
                                        .padding(12)
                                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(AppTheme.surfaceElevated(scheme)))
                                        .accessibilityLabel("Spotify Client ID")

                                    Button {
                                        startConnect(savingCustomID: true)
                                    } label: {
                                        Text("Save Custom ID & Connect")
                                            .font(.system(size: 14, weight: .bold))
                                            .frame(maxWidth: .infinity)
                                            .frame(minHeight: 44)
                                            .background(AppTheme.surfaceElevated(scheme))
                                            .foregroundColor(AppTheme.fg(scheme))
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                    .disabled(trimmedClientID.isEmpty || isConnecting)
                                }
                                .padding(.top, 12)
                            },
                            label: {
                                Text("Hit a beta limit (403)? Use your own free Client ID")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(AppTheme.fg(scheme))
                            }
                        )
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(AppTheme.surface(scheme)))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppTheme.border(scheme), lineWidth: 1))
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

    private func startConnect(savingCustomID: Bool) {
        let previousCustomID = SpotifyClientIDStore.stored
        if savingCustomID {
            SpotifyClientIDStore.stored = trimmedClientID.isEmpty ? nil : trimmedClientID
        }
        isConnecting = true
        errorMessage = nil
        Task {
            do {
                try await spotifyAuth.connect()
                isConnecting = false
                onConnected?()
                dismiss()
            } catch {
                if savingCustomID {
                    // Restore previous Client ID on cancelled/failed custom connect
                    SpotifyClientIDStore.stored = previousCustomID
                }
                isConnecting = false
                errorMessage = error.localizedDescription
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
