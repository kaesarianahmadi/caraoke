import SwiftUI

/// Settings screen (design: design/screens/settings.html — locked 2026-09-05).
/// Sections: Connect music (service marks), Appearance (bottom-sheet picker),
/// Support us, Contact & about. The Caraoke Plus entry rides the top of
/// Connect music; Spotify's bring-your-own-Client-ID flow expands under its
/// row; LRCLIB attribution lives in the Connect-music note.
/// Reached from the home screen's gear button — no tab bar per PRD D7.
struct SettingsView: View {
    @ObservedObject var model: RideModeViewModel
    var presentingPaywall: Binding<Bool>
    /// Shared auth — the same object the playback pipeline uses (injected by
    /// the VM), so connecting here connects the pipeline and vice versa.
    @ObservedObject var spotifyAuth: SpotifyAuth
    var cache = LyricsDiskCache(directory: LyricsDiskCache.defaultDirectory())
    @State private var cacheCleared = false
    @State private var clientIDText = SpotifyClientIDStore.stored ?? ""
    @State private var showAppearanceSheet = false
    @State private var spotifyFlowExpanded = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background(scheme)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        connectMusicSection
                        appearanceSection
                        supportSection
                        contactSection
                        footnote
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(AppearanceSettings.preferredScheme)
        .sheet(isPresented: $showAppearanceSheet) {
            AppearanceSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Design primitives (settings.html `.sectionlabel`/`.group`/`.g-row`)

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(AppTheme.muted(scheme))
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
    }

    private func group<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.surface(scheme)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.border(scheme), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func rowDivider() -> some View {
        Divider().overlay(AppTheme.border(scheme))
    }

    /// 29×29 circular icon slot (`.g-icon`).
    private func iconCircle(_ systemName: String) -> some View {
        ZStack {
            Circle().fill(AppTheme.fg(scheme).opacity(0.10))
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppTheme.fg(scheme))
        }
        .frame(width: 29, height: 29)
    }

    // MARK: - Connect music (+ Caraoke Plus + Spotify flow)

    @ViewBuilder
    private var connectMusicSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Connect music")
            group {
                Button { presentingPaywall.wrappedValue = true } label: {
                    gRow {
                        iconCircle("star.fill")
                        Text("Caraoke Plus").gLabel()
                        Text("View").gValue(scheme)
                        Image(systemName: "chevron.right").gChevron()
                    }
                }
                .buttonStyle(.plain)
                rowDivider()
                if FeatureFlags.spotifyEnabled {
                    spotifyRow
                    if spotifyFlowExpanded {
                        spotifyFlow
                        rowDivider()
                    }
                    rowDivider()
                }
                appleMusicRow
            }
            Text("Pick the app Caraoke listens to for track and timing data.")
                .gNote(scheme)
        }
    }

    private var appleMusicRow: some View {
        gRow {
            AppleMusicLogo().frame(width: 29, height: 29)
            Text("Apple Music").gLabel()
            Text("Connected")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AppTheme.ok)
        }
    }

    @ViewBuilder
    private var spotifyRow: some View {
        Button {
            withAnimation { spotifyFlowExpanded.toggle() }
        } label: {
            gRow {
                SpotifyLogo().frame(width: 29, height: 29)
                Text("Spotify").gLabel()
                if spotifyAuth.needsReconnect {
                    Text("Reconnect needed")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.warn)
                } else {
                    Text(spotifyAuth.isConnected ? "Connected" : "Not connected")
                        .font(.system(size: 13, weight: spotifyAuth.isConnected ? .medium : .regular))
                        .foregroundColor(spotifyAuth.isConnected ? AppTheme.ok : AppTheme.warn)
                }
                Image(systemName: "chevron.right")
                    .gChevron()
                    .rotationEffect(.degrees(spotifyFlowExpanded ? 90 : 0))
            }
        }
        .buttonStyle(.plain)
    }

    /// Bring-your-own Client ID (user decision 2026-08-31): the user creates
    /// a private development-mode Spotify app and pastes its Client ID; as
    /// the app's owner they are exempt from the developer's own allowlist.
    /// Token stays in the Keychain; the shared auth instance serves the
    /// playback pipeline.
    @ViewBuilder
    private var spotifyFlow: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !SpotifyClientIDStore.hasClientID {
                Text("Create a private Spotify app at developer.spotify.com/dashboard, enable the Web API, add caraoke:// as a redirect URI, then paste its Client ID here.")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.muted(scheme))
                    .lineSpacing(1.45 * 13 - 13)
            }
            TextField("Paste your Client ID", text: $clientIDText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 13).monospaced())
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.fg(scheme).opacity(0.06)))
            HStack {
                Button("Save") {
                    SpotifyClientIDStore.stored = clientIDText.trimmingCharacters(in: .whitespaces)
                }
                .font(.system(size: 14, weight: .medium))
                .disabled(clientIDText.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
                if spotifyAuth.isConnected {
                    Button("Disconnect", role: .destructive) {
                        spotifyAuth.disconnect()
                    }
                    .font(.system(size: 14, weight: .medium))
                } else {
                    Button("Connect") {
                        Task { try? await spotifyAuth.connect() }
                    }
                    .font(.system(size: 14, weight: .medium))
                    .disabled(!SpotifyClientIDStore.hasClientID)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var spotifyFlowExpandedInitial: Bool {
        !SpotifyClientIDStore.hasClientID || !spotifyAuth.isConnected
    }

    // MARK: - Appearance (design bottom sheet)

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Appearance")
            group {
                Button {
                    showAppearanceSheet = true
                } label: {
                    gRow {
                        iconCircle(AppearanceSettings.mode == .dark
                                   ? "moon.fill"
                                   : AppearanceSettings.mode == .light ? "sun.max.fill" : "circle.lefthalf.filled")
                        Text("Appearance").gLabel()
                        Text(AppearanceSettings.mode.shortLabel).gValue(scheme)
                        Image(systemName: "chevron.right").gChevron()
                    }
                }
                .buttonStyle(.plain)
            }
            Text("Dark keeps the night-drive look; Auto follows the device setting.")
                .gNote(scheme)
        }
    }

    // MARK: - Support us

    private var supportSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Support us")
            group {
                rateRow
                rowDivider()
                shareRow
            }
        }
    }

    /// Rate on the App Store (product 10-5-105 per the locked-decisions doc;
    /// app id filled in at submission).
    private var rateRow: some View {
        gRow {
            iconCircle("star.fill")
            Text("Rate Caraoke").gLabel()
            Image(systemName: "chevron.right").gChevron()
        }
        .contentShape(Rectangle())
    }

    private var shareRow: some View {
        gRow {
            iconCircle("square.and.arrow.up")
            Text("Share with friends").gLabel()
            Image(systemName: "chevron.right").gChevron()
        }
        .contentShape(Rectangle())
    }

    // MARK: - Contact & about

    private var contactSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Contact & about")
            group {
                Button {
                    if let url = URL(string: "mailto:support@caraoke.app") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    gRow {
                        iconCircle("circle.grid.cross")
                        Text("Feedback").gLabel()
                        Image(systemName: "chevron.right").gChevron()
                    }
                }
                .buttonStyle(.plain)
                rowDivider()
                aboutRow
            }
        }
    }

    private var aboutRow: some View {
        gRow {
            BrandMark()
                .frame(width: 26, height: 26)
                .foregroundColor(AppTheme.accent(scheme))
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.fg(scheme).opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppTheme.border(scheme), lineWidth: 1))
            Text("Caraoke").gLabel()
            Text(versionText).gValue(scheme)
        }
    }

    private var footnote: some View {
        Text("Caraoke \(versionText) · Made for passengers · Lyrics © their respective rights holders")
            .font(.system(size: 11))
            .tracking(0.02 * 11)
            .foregroundColor(AppTheme.muted(scheme))
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }

    private var versionText: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }

    /// Standard row layout: icon + label + optional trailing, 13/16 padding.
    private func gRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(minHeight: 52, alignment: .leading)
        .contentShape(Rectangle())
    }
}

// MARK: - Row helper modifiers (g-label / g-value / g-chev / g-note)
//
// gLabel/gChevron resolve the palette through @Environment so they follow
// the real appearance instead of a default-constructed EnvironmentValues.

private struct GLabelModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .font(.system(size: 15))
            .foregroundColor(AppTheme.fg(scheme))
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
    }
}

private struct GChevronModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(AppTheme.muted(scheme))
    }
}

private extension View {
    /// `.g-label` — 15px primary row label.
    func gLabel() -> some View { modifier(GLabelModifier()) }

    /// `.g-value` — 15px muted trailing value.
    func gValue(_ scheme: ColorScheme) -> some View {
        font(.system(size: 15))
            .foregroundColor(AppTheme.muted(scheme))
    }

    /// `.g-chev` — 8px chevron built from the SF Symbol.
    func gChevron() -> some View { modifier(GChevronModifier()) }

    /// `.g-note` — 13px muted note under a group.
    func gNote(_ scheme: ColorScheme) -> some View {
        font(.system(size: 13))
            .lineSpacing(1.45 * 13 - 13)
            .foregroundColor(AppTheme.muted(scheme))
            .padding(.horizontal, 4)
            .padding(.top, 8)
    }
}

// MARK: - Appearance bottom sheet (design `.sheet`)

struct AppearanceSheet: View {
    @State private var mode = AppearanceSettings.mode
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Appearance")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(AppTheme.fg(scheme))
                Spacer()
                Button("Done") { dismiss() }
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(AppTheme.accent(scheme))
            }
            VStack(spacing: 0) {
                ForEach(AppearanceMode.allCases) { m in
                    Button {
                        mode = m
                        AppearanceSettings.mode = m
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(AppTheme.fg(scheme).opacity(0.10))
                                Image(systemName: icon(for: m))
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(AppTheme.fg(scheme))
                            }
                            .frame(width: 29, height: 29)
                            Text(m.sheetLabel)
                                .font(.system(size: 15))
                                .foregroundColor(AppTheme.fg(scheme))
                            Spacer()
                            if mode == m {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(AppTheme.ok)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.surface(scheme)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.border(scheme), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            Spacer()
        }
        .padding(20)
        .background(AppTheme.bg(scheme).ignoresSafeArea())
        .preferredColorScheme(AppearanceSettings.preferredScheme)
    }

    private func icon(for mode: AppearanceMode) -> String {
        switch mode {
        case .auto: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}