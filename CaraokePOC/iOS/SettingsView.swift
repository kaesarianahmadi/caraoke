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

    /// Public Spotify section (user decision 2026-08-31). Development mode
    /// allows only 5 allowlisted accounts; non-allowlisted users get 403, so
    /// the UI says "limited beta" instead of implying full support. Shares
    /// the Keychain token with the playback pipeline.
    @ViewBuilder
    private var spotifySection: some View {
        Section {
            if spotifyAuth.hasClientID {
                LabeledContent("Connection", value: spotifyAuth.isConnected ? "Connected" : "Not connected")
                if spotifyAuth.isConnected {
                    Button("Disconnect Spotify") { spotifyAuth.disconnect() }
                } else {
                    Button("Connect Spotify") {
                        Task { try? await spotifyAuth.connect() }
                    }
                }
            } else {
                Text("Add your Spotify Client ID to Secrets.plist to enable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Spotify (beta)")
        } footer: {
            Text("Spotify support is currently a limited beta: access is restricted to a small allowlist of testers during development mode. Apple Music is fully supported.")
        }
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
