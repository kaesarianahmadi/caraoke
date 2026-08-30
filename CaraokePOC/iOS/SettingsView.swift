import SwiftUI

/// Settings sheet: attribution (required etiquette for community lyrics),
/// support links, ride stats, and cache control. Reached from the home
/// screen's gear button — no tab bar per PRD D7.
struct SettingsView: View {
    @ObservedObject var model: RideModeViewModel
    var presentingPaywall: Binding<Bool>
    var cache = LyricsDiskCache(directory: LyricsDiskCache.defaultDirectory())
    @State private var cacheCleared = false
    @StateObject private var spotifyAuth = SpotifyAuth()
    @State private var clientIDText = SpotifyClientIDStore.stored ?? ""

    var body: some View {
        NavigationStack {
            List {
                Section("Caraoke Plus") {
                    Button {
                        presentingPaywall.wrappedValue = true
                    } label: {
                        LabeledContent("Plans & pricing", value: "View")
                    }
                }

                if FeatureFlags.spotifyEnabled {
                    spotifySection
                }

                Section("Ride") {
                    LabeledContent("Total ride time", value: durationText(model.totalRideMs))
                    Button("Reset ride stats", role: .destructive) {
                        model.resetStats()
                    }
                }

                Section {
                    LabeledContent("Lyrics", value: "Community lyrics via LRCLIB")
                    Link("lrclib.net", destination: URL(string: "https://lrclib.net")!)
                    // Etiquette + goodwill for the free service the product
                    // rides on; see the locked-decisions document.
                    Link("Support LRCLIB", destination: URL(string: "https://lrclib.net")!)
                } header: {
                    Text("Lyrics")
                } footer: {
                    Text("Synced lyrics come from LRCLIB, a free community lyrics database.")
                }

                Section("Storage") {
                    Button("Clear downloaded lyrics cache") {
                        cache.clearAll()
                        cacheCleared = true
                    }
                    if cacheCleared {
                        Text("Cache cleared.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Support") {
                    Link("Contact support", destination: URL(string: "mailto:support@caraoke.app")!)
                }

                Section {
                    LabeledContent("Version", value: versionText)
                } footer: {
                    Text("Use while parked · Designed for passengers. Lyrics © their respective rights holders.")
                }
            }
            .navigationTitle("Settings")
        }
    }

    /// Public Spotify section (user decision 2026-08-31) using the same
    /// "bring your own Client ID" model the category leader adopted: the
    /// user creates a private development-mode Spotify app and pastes its
    /// Client ID. As the app's owner they are exempt from the developer's
    /// own allowlist — this scales to every user instead of 5 testers.
    /// The token stays in the Keychain; the same store serves the playback
    /// pipeline.
    @ViewBuilder
    private var spotifySection: some View {
        Section {
            if !SpotifyClientIDStore.hasClientID {
                guideRows
            }
            TextField("Paste your Client ID", text: $clientIDText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.caption.monospaced())
            Button("Save Client ID") {
                SpotifyClientIDStore.stored = clientIDText.trimmingCharacters(in: .whitespaces)
            }
            .disabled(clientIDText.trimmingCharacters(in: .whitespaces).isEmpty)

            if SpotifyClientIDStore.hasClientID {
                LabeledContent("Connection", value: spotifyAuth.isConnected ? "Connected" : "Not connected")
                if spotifyAuth.needsReconnect {
                    Text("Spotify needs to be reconnected. Tap Connect again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if spotifyAuth.isConnected {
                    Button("Disconnect Spotify", role: .destructive) { spotifyAuth.disconnect() }
                } else {
                    Button("Connect Spotify") {
                        Task { try? await spotifyAuth.connect() }
                    }
                }
            }
        } header: {
            Text("Spotify")
        } footer: {
            Text("Connect Spotify with your own Spotify app (2–3 minutes, see steps above). A Spotify Premium subscription is required for the lyrics API, and the token stays on this device.")
        }
    }

    /// The 2–3 minute setup guide, mirroring the category-standard flow.
    @ViewBuilder
    private var guideRows: some View {
        Text("1. Open developer.spotify.com/dashboard in your browser and log in.")
            .font(.caption)
        Text("2. Accept the developer terms, then tap Create app.")
            .font(.caption)
        Text("3. Name it anything; Redirect URI: caraoke://callback")
            .font(.caption.monospaced())
        Text("4. Tick iOS under which APIs/SDKs, then Save.")
            .font(.caption)
        Text("5. Open the app's settings and copy the Client ID.")
            .font(.caption)
    }

    private var versionText: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(v) (\(b))"
    }

    private func durationText(_ ms: Int) -> String {
        let totalSeconds = ms / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
