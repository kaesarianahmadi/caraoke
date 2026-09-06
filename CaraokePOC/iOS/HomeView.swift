import SwiftUI
import UIKit

/// Home screen (design: design/screens/home.html, "Night Podium", states
/// A/B/C/D): brand header + settings gear, the Live Lyrics master switch card
/// (with the Live Activities gate), the now-playing player card (same layout
/// as the Lock Screen tile, palette-following), music sources, and the
/// "Needs attention" section — shown only when something needs fixing.
struct HomeView: View {
    @ObservedObject var model: RideModeViewModel
    @State private var showSettings = false
    @State private var showPaywall = false
    @State private var showSpotifySetup = false
    @StateObject private var purchases = PurchaseManager()
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            AppTheme.background(scheme)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    switchCard
                    // Design states A/C: card shows only with real track
                    // content (state B — ride on, no music — hides it).
                    if !model.trackTitle.isEmpty || !model.currentLine.isEmpty {
                        playerCard
                    }
                    sourcesSection
                    if showsFixes {
                        fixesSection
                    }
                    footnote
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
        }
        .preferredColorScheme(AppearanceSettings.preferredScheme)
        .sheet(isPresented: $showSettings) {
            SettingsView(model: model, presentingPaywall: $showPaywall,
                         spotifyAuth: model.spotifyAuth)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(purchases: purchases, onDismiss: { showPaywall = false })
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showSpotifySetup) {
            SpotifySetupView(spotifyAuth: model.spotifyAuth, onConnected: {
                model.selectMusicSource(.spotify)
            })
        }
    }

    // MARK: - Header (brand mark + gear)

    private var header: some View {
        HStack {
            HStack(spacing: 10) {
                CaraokeLogo(size: 27)
                Text("Caraoke")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.02 * 28)
            }
            Spacer()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(AppTheme.fg(scheme))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(AppTheme.surface(scheme)))
                    .overlay(Circle().stroke(AppTheme.border(scheme), lineWidth: 1))
            }
            .accessibilityLabel("Settings")
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Live Lyrics switch card (state A/B/C/D master)

    private var switchCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Live Lyrics")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppTheme.fg(scheme))
                    Text("Puts synced lyrics on CarPlay and Lock Screen while your music plays.")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.muted(scheme))
                        .lineSpacing(1.45 * 13 - 13)
                        .padding(.top, 6)
                }
                Spacer(minLength: 12)
                Toggle("", isOn: Binding(
                    get: { model.isOn },
                    set: { _ in model.toggle() }
                ))
                .labelsHidden()
                .tint(AppTheme.ok)
                .fixedSize()
            }
            if model.liveActivityGateMessage != nil {
                gateBanner
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(AppTheme.surface(scheme)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(AppTheme.border(scheme), lineWidth: 1))
    }

    /// Design `.gate`: amber warning box under the switch (state D).
    private var gateBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundColor(AppTheme.warn)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.liveActivityGateMessage ?? "Live Activities is turned off.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.fg(scheme))
                Text("The switch stays On, but lyrics can't reach the car screen until Live Activities is enabled.")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.muted(scheme))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(AppTheme.warn.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(AppTheme.warn.opacity(0.45), lineWidth: 1))
        .padding(.top, 12)
    }

    /// Design `.fixes` visibility: gate banner OR lyrics not reachable.
    private var showsFixes: Bool {
        model.liveActivityGateMessage != nil
    }

    // MARK: - Player card (same layout as the LA tile, palette-following)

    private var playerCard: some View {
        LyricTileView(
            title: model.trackTitle,
            artist: model.trackArtist,
            currentLine: model.currentLine,
            nextLine: model.nextLine,
            isPlaying: model.isPlaying,
            progress: model.progress,
            status: model.lyricStatus,
            positionMs: model.positionMs,
            durationMs: model.durationMs,
            isHome: true,
            palette: .home(scheme)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(scheme == .dark ? 0.22 : 0.06), radius: 10, y: 4)
        .accessibilityLabel("Now playing")
    }

    // MARK: - Music sources (Mutual exclusion: Spotify XOR Apple Music)

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Music sources")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppTheme.muted(scheme))
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
            VStack(spacing: 0) {
                Button {
                    model.selectMusicSource(.appleMusic)
                } label: {
                    sourceRow(
                        logo: AnyView(AppleMusicLogo()),
                        title: "Apple Music",
                        subtitle: model.appleMusicConnected ? "Active source" : "Tap to switch",
                        connected: model.appleMusicConnected,
                        showsCheck: model.appleMusicConnected
                    )
                }
                .buttonStyle(.plain)

                Divider().overlay(AppTheme.border(scheme))

                if FeatureFlags.spotifyEnabled {
                    Button {
                        if model.spotifyAuth.isConnected {
                            model.selectMusicSource(.spotify)
                        } else {
                            showSpotifySetup = true
                        }
                    } label: {
                        sourceRow(
                            logo: AnyView(SpotifyLogo(size: 34)),
                            title: "Spotify",
                            subtitle: model.spotifyConnected
                                ? "Active source"
                                : (model.spotifyAuth.isConnected ? "Connected (tap to switch)" : "Not connected"),
                            connected: model.spotifyConnected,
                            showsCheck: model.spotifyConnected
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.surface(scheme)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.border(scheme), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func sourceRow(logo: AnyView, title: String, subtitle: String,
                           connected: Bool, showsCheck: Bool) -> some View {
        HStack(spacing: 12) {
            logo.frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(AppTheme.fg(scheme))
                Text(subtitle)
                    .font(.system(size: 13, weight: connected ? .medium : .regular))
                    .foregroundColor(connected ? AppTheme.ok : AppTheme.muted(scheme))
            }
            Spacer()
            if showsCheck && connected {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.ok)
            } else if !connected {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.muted(scheme))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    // MARK: - Needs attention (state D)

    @ViewBuilder
    private var fixesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Needs attention")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppTheme.muted(scheme))
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(AppTheme.fg(scheme).opacity(0.06))
                    .frame(width: 34, height: 34)
                    .overlay(Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(AppTheme.warn))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live Activities is off")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(AppTheme.fg(scheme))
                    Text("Lyrics can't reach CarPlay until it's enabled.")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.muted(scheme))
                }
                Spacer()
                Button("Fix") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(AppTheme.fg(scheme))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.surface(scheme)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.border(scheme), lineWidth: 1))
        }
    }

    private var footnote: some View {
        Text("Use while parked · Designed for passengers")
            .font(.system(size: 11))
            .tracking(0.02 * 11)
            .foregroundColor(AppTheme.muted(scheme))
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }
}

// MARK: - Source logo (Apple Music)

struct AppleMusicLogo: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0xFB5C74), Color(hex: 0xFA233B)],
                           startPoint: .top, endPoint: .bottom)
            Image(systemName: "music.note")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
