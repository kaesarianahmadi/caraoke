import SwiftUI
import UIKit

/// Settings screen: 4 coherent groups (Music Sources, Cockpit & Display, Caraoke Plus, Guidance & About).
struct SettingsView: View {
    @ObservedObject var model: RideModeViewModel
    var presentingPaywall: Binding<Bool>
    @ObservedObject var spotifyAuth: SpotifyAuth

    @State private var showSpotifySetup = false
    @State private var showOnboarding = false

    @AppStorage(AppearanceSettings.storageKey) private var appearanceRaw: String = AppearanceMode.auto.rawValue
    @AppStorage(AppearanceSettings.boldTextKey) private var boldText = true
    @AppStorage(AppearanceSettings.homeLayoutKey) private var layoutRaw = HomeLayoutMode.stageFocus.rawValue
    @AppStorage(AppearanceSettings.backdropStyleKey) private var backdropRaw = LyricsBackdropStyle.ambientCover.rawValue
    @AppStorage(AppearanceSettings.showTranslationsKey) private var showTranslations = true
    @AppStorage(AppearanceSettings.autoOpenLyricsKey) private var autoOpenLyrics = false

    @Environment(\.colorScheme) private var scheme

    private var currentAppearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceRaw) ?? .auto
    }

    var body: some View {
        ZStack {
            AppTheme.bg(scheme).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    musicSourcesSection
                    cockpitDisplaySection
                    caraokePlusSection
                    guidanceAboutSection
                    versionFootnote
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .tint(AppTheme.accent(scheme))
        .preferredColorScheme(currentAppearanceMode.colorScheme)
        .onChange(of: appearanceRaw) { _, newValue in
            if let mode = AppearanceMode(rawValue: newValue) {
                AppearanceSettings.apply(mode: mode)
            }
        }
        .onChange(of: spotifyAuth.isConnected) { _, connected in
            if !connected, model.activeSource == .spotify {
                model.selectMusicSource(.appleMusic)
            }
        }
        .sheet(isPresented: $showSpotifySetup) {
            SpotifySetupView(spotifyAuth: spotifyAuth, onConnected: {
                model.selectMusicSource(.spotify)
            })
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(onDismiss: { showOnboarding = false })
        }
    }

    // MARK: - 1. Music Sources

    private var musicSourcesSection: some View {
        sectionGroup(title: "Music Sources") {
            VStack(spacing: 0) {
                sourceRow(
                    title: "Automatic",
                    subtitle: "Follow whichever player starts",
                    icon: {
                        Image(systemName: "sparkles")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AppTheme.accent(scheme))
                            .frame(width: 28, height: 28)
                    },
                    badge: model.activeSource == .auto ? "Active" : nil,
                    badgeColor: AppTheme.ok
                ) {
                    model.selectMusicSource(.auto)
                }

                Divider().overlay(AppTheme.border(scheme))

                sourceRow(
                    title: "Apple Music",
                    subtitle: model.appleMusicAuthDenied ? "Permission denied in iOS Settings" : "Built-in Music app",
                    icon: { AppleMusicLogo(size: 28) },
                    badge: model.appleMusicAuthDenied ? "Denied" : (model.activeSource == .appleMusic ? "Active" : nil),
                    badgeColor: model.appleMusicAuthDenied ? AppTheme.err : AppTheme.ok
                ) {
                    if model.appleMusicAuthDenied, let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    } else {
                        model.selectMusicSource(.appleMusic)
                    }
                }

                Divider().overlay(AppTheme.border(scheme))

                HStack(spacing: 12) {
                    SpotifyLogo(size: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Spotify")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(AppTheme.fg(scheme))
                        Text(spotifySubtitle)
                            .font(.caption)
                            .foregroundColor(model.spotifyNeedsAllowlist ? AppTheme.warn : AppTheme.muted(scheme))
                    }
                    Spacer()
                    if let badge = spotifyBadge {
                        Text(badge.text)
                            .font(.caption2.weight(.bold))
                            .foregroundColor(badge.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(badge.color.opacity(0.14)))
                    }
                    Button {
                        showSpotifySetup = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.muted(scheme))
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(AppTheme.surfaceElevated(scheme)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Configure Spotify")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                .onTapGesture {
                    if spotifyAuth.isConnected && !spotifyAuth.needsReconnect && !model.spotifyNeedsAllowlist {
                        model.selectMusicSource(.spotify)
                    } else {
                        showSpotifySetup = true
                    }
                }
            }
        }
    }

    private var spotifySubtitle: String {
        if model.spotifyNeedsAllowlist { return "403 beta limit — add your Client ID" }
        if spotifyAuth.needsReconnect { return "Reconnect needed" }
        if spotifyAuth.isConnected { return model.activeSource == .spotify ? "Connected · Active" : "Connected · Tap to switch" }
        return "Not connected"
    }

    private var spotifyBadge: (text: String, color: Color)? {
        if model.spotifyNeedsAllowlist { return ("403", AppTheme.warn) }
        if spotifyAuth.needsReconnect { return ("Reconnect", AppTheme.warn) }
        if model.activeSource == .spotify && spotifyAuth.isConnected { return ("Active", AppTheme.ok) }
        return nil
    }

    private func sourceRow<Icon: View>(
        title: String,
        subtitle: String,
        @ViewBuilder icon: () -> Icon,
        badge: String?,
        badgeColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                icon()
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppTheme.fg(scheme))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(AppTheme.muted(scheme))
                }
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.caption2.weight(.bold))
                        .foregroundColor(badgeColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(badgeColor.opacity(0.14)))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 2. Cockpit & Display

    private var cockpitDisplaySection: some View {
        sectionGroup(title: "Cockpit & Display") {
            VStack(spacing: 0) {
                HStack {
                    Text("Appearance")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(AppTheme.fg(scheme))
                    Spacer()
                    Picker("Appearance", selection: $appearanceRaw) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.shortLabel).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)

                Divider().overlay(AppTheme.border(scheme))

                HStack {
                    Text("Home Layout")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(AppTheme.fg(scheme))
                    Spacer()
                    Picker("Home Layout", selection: $layoutRaw) {
                        ForEach(HomeLayoutMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)

                Divider().overlay(AppTheme.border(scheme))

                HStack {
                    Text("Lyrics Backdrop")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(AppTheme.fg(scheme))
                    Spacer()
                    Picker("Lyrics Backdrop", selection: $backdropRaw) {
                        ForEach(LyricsBackdropStyle.allCases) { style in
                            Text(style.title).tag(style.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)

                Divider().overlay(AppTheme.border(scheme))

                Toggle("Bold Lyrics", isOn: $boldText)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                Divider().overlay(AppTheme.border(scheme))

                Toggle("Bilingual Translations", isOn: $showTranslations)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                Divider().overlay(AppTheme.border(scheme))

                Toggle("Open Full Lyrics on Launch", isOn: $autoOpenLyrics)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                Divider().overlay(AppTheme.border(scheme))

                NavigationLink {
                    WidgetSettingsView(model: model)
                } label: {
                    HStack {
                        Text("Surfaces & Widgets")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(AppTheme.fg(scheme))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundColor(AppTheme.muted(scheme))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 3. Caraoke Plus

    private var caraokePlusSection: some View {
        sectionGroup(title: "Caraoke Plus") {
            Button {
                presentingPaywall.wrappedValue = true
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.accent(scheme).opacity(0.18))
                            .frame(width: 34, height: 34)
                        Image(systemName: "crown.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(AppTheme.accent(scheme))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Caraoke Plus")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(AppTheme.fg(scheme))
                        Text("3-day free trial · CarPlay, Island & Widgets")
                            .font(.caption)
                            .foregroundColor(AppTheme.muted(scheme))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundColor(AppTheme.muted(scheme))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 4. Guidance & About

    private var guidanceAboutSection: some View {
        sectionGroup(title: "Guidance & About") {
            VStack(spacing: 0) {
                NavigationLink {
                    HelpView()
                } label: {
                    navRowLabel(icon: "book.closed.fill", title: "Visual Setup Guide")
                }
                .buttonStyle(.plain)

                Divider().overlay(AppTheme.border(scheme))

                Button {
                    showOnboarding = true
                } label: {
                    navRowLabel(icon: "sparkles.rectangle.stack.fill", title: "Replay Welcome Tour")
                }
                .buttonStyle(.plain)

                Divider().overlay(AppTheme.border(scheme))

                Link(destination: URL(string: "https://caraokeapp.com/privacy")!) {
                    navRowLabel(icon: "hand.raised.fill", title: "Privacy Policy", external: true)
                }

                Divider().overlay(AppTheme.border(scheme))

                Link(destination: URL(string: "https://caraokeapp.com/terms")!) {
                    navRowLabel(icon: "doc.text.fill", title: "Terms of Use", external: true)
                }
            }
        }
    }

    private func navRowLabel(icon: String, title: String, external: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(AppTheme.muted(scheme))
                .frame(width: 24)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundColor(AppTheme.fg(scheme))
            Spacer()
            Image(systemName: external ? "arrow.up.right" : "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundColor(AppTheme.muted(scheme))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    private var versionFootnote: some View {
        let ver = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
        return Text("Caraoke \(ver) · Made for passengers · Lyrics © their respective rights holders")
            .font(.caption2)
            .foregroundColor(AppTheme.muted(scheme))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }

    private func sectionGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .foregroundColor(AppTheme.muted(scheme))
                .padding(.leading, 4)

            content()
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(AppTheme.surface(scheme)))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AppTheme.border(scheme), lineWidth: 1))
        }
    }
}
