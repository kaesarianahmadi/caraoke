import SwiftUI
import UIKit

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
    @State private var clientIDText = SpotifyClientIDStore.stored ?? ""
    @State private var showAppearanceSheet = false
    @State private var spotifyFlowExpanded = false
    @State private var copiedRedirect = false
    @State private var isConnectingSpotify = false
    @State private var spotifyErrorMessage: String?
    @AppStorage(AppearanceSettings.storageKey) private var appearanceRaw: String = AppearanceMode.auto.rawValue
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    private var currentAppearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceRaw) ?? .auto
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background(scheme)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        caraokePlusSection
                        connectMusicSection
                        appearanceSection
                        supportAndAboutSection
                        footnote
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Design back arrow (settings.html header) — dismisses the
                // sheet back to Home.
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(AppTheme.fg(scheme))
                    }
                    .accessibilityLabel("Back")
                }
            }
        }
        .preferredColorScheme(currentAppearanceMode.colorScheme)
        .sheet(isPresented: $showAppearanceSheet) {
            AppearanceSheet()
                .preferredColorScheme(currentAppearanceMode.colorScheme)
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

    /// 29×29 circular icon slot (`.g-icon`): the design's mid-slate disc with
    /// a white glyph, same fill for every row in both palettes.
    private func iconCircle(_ systemName: String) -> some View {
        ZStack {
            Circle().fill(Color(hex: 0x56616F))
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
        }
        .frame(width: 29, height: 29)
    }

    // MARK: - Caraoke Plus (subscription entry; own group above Connect music)

    private var caraokePlusSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Caraoke Plus")
            group {
                Button { presentingPaywall.wrappedValue = true } label: {
                    gRow {
                        iconCircle("star.fill")
                        Text("Plans & pricing").gLabel()
                        Text("View").gValue(scheme)
                        Image(systemName: "chevron.right").gChevron()
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Connect music (+ Spotify Client-ID flow)

    @ViewBuilder
    private var connectMusicSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Connect music")
            group {
                appleMusicRow
                if FeatureFlags.spotifyEnabled {
                    rowDivider()
                    spotifyRow
                    if spotifyFlowExpanded {
                        spotifyFlow
                    }
                }
            }
            Text("Pick the app Caraoke listens to for track and timing data.")
                .gNote(scheme)
        }
    }

    private var appleMusicRow: some View {
        Button {
            model.selectMusicSource(.appleMusic)
        } label: {
            gRow {
                AppleMusicLogo().frame(width: 29, height: 29)
                Text("Apple Music").gLabel()
                Text(model.appleMusicConnected ? "Active source" : "Standby")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(model.appleMusicConnected ? AppTheme.ok : AppTheme.muted(scheme))
                if model.appleMusicConnected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.ok)
                } else {
                    Image(systemName: "chevron.right")
                        .gChevron()
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var spotifyRow: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { spotifyFlowExpanded.toggle() }
        } label: {
            gRow {
                SpotifyLogo().frame(width: 29, height: 29)
                Text("Spotify").gLabel()
                if model.spotifyConnected {
                    Text("Active source")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.ok)
                } else if spotifyAuth.needsReconnect {
                    Text("Reconnect needed")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.warn)
                } else if spotifyAuth.isConnected {
                    Text("Connected (Standby)")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(AppTheme.muted(scheme))
                } else {
                    Text("Not connected")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(AppTheme.warn)
                }
                if model.spotifyConnected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.ok)
                } else {
                    Image(systemName: "chevron.right")
                        .gChevron()
                        .rotationEffect(.degrees(spotifyFlowExpanded ? 90 : 0))
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// Bring-your-own Client ID setup with direct links and instructions
    @ViewBuilder
    private var spotifyFlow: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text("How to get your Spotify Client ID:")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.fg(scheme))

                // Step 1: Dashboard Link
                HStack(spacing: 8) {
                    Text("1.")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AppTheme.accent(scheme))
                    Link(destination: URL(string: "https://developer.spotify.com/dashboard")!) {
                        HStack(spacing: 4) {
                            Text("Open Spotify Developer Dashboard")
                                .font(.system(size: 12, weight: .medium))
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(AppTheme.accent(scheme))
                    }
                }

                // Step 2: Create App
                HStack(alignment: .top, spacing: 8) {
                    Text("2.")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AppTheme.accent(scheme))
                    Text("Log in, tap 'Create app', name it 'Caraoke' and select 'Web API'.")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.muted(scheme))
                }

                // Step 3: Redirect URI with Copy
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 8) {
                        Text("3.")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(AppTheme.accent(scheme))
                        Text("Under App Settings → Redirect URIs, add:")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.muted(scheme))
                    }
                    HStack {
                        Text("caraoke://spotify-callback")
                            .font(.system(size: 12, weight: .semibold).monospaced())
                            .foregroundColor(AppTheme.fg(scheme))
                        Spacer()
                        Button {
                            UIPasteboard.general.string = "caraoke://spotify-callback"
                            copiedRedirect = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                copiedRedirect = false
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: copiedRedirect ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 11))
                                Text(copiedRedirect ? "Copied" : "Copy")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(copiedRedirect ? AppTheme.ok : AppTheme.accent(scheme))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(AppTheme.fg(scheme).opacity(0.08)))
                        }
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppTheme.fg(scheme).opacity(0.04)))
                }

                // Step 4: Copy Client ID
                HStack(alignment: .top, spacing: 8) {
                    Text("4.")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AppTheme.accent(scheme))
                    Text("Copy your Client ID from Basic Information and paste below:")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.muted(scheme))
                }
            }

            // Input field
            HStack(spacing: 8) {
                TextField("Paste Client ID here", text: $clientIDText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 13).monospaced())
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.fg(scheme).opacity(0.06)))

                Button {
                    if let clip = UIPasteboard.general.string {
                        clientIDText = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } label: {
                    Text("Paste")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AppTheme.fg(scheme).opacity(0.08)))
                }
                .foregroundColor(AppTheme.fg(scheme))
            }

            if let spotifyErrorMessage {
                Text(spotifyErrorMessage)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.warn)
            }

            // Action buttons
            HStack(spacing: 10) {
                Button {
                    let trimmed = clientIDText.trimmingCharacters(in: .whitespacesAndNewlines)
                    SpotifyClientIDStore.stored = trimmed
                    isConnectingSpotify = true
                    spotifyErrorMessage = nil
                    Task {
                        do {
                            try await spotifyAuth.connect()
                            isConnectingSpotify = false
                            model.selectMusicSource(.spotify)
                        } catch {
                            isConnectingSpotify = false
                            spotifyErrorMessage = error.localizedDescription
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isConnectingSpotify {
                            ProgressView().tint(.white)
                                .scaleEffect(0.8)
                        }
                        Text(spotifyAuth.isConnected ? "Reconnect" : "Save & Connect")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(clientIDText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              ? Color.gray : Color(hex: 0x1DB954)))
                }
                .disabled(clientIDText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isConnectingSpotify)

                if spotifyAuth.isConnected && !model.spotifyConnected {
                    Button {
                        model.selectMusicSource(.spotify)
                    } label: {
                        Text("Make Active")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppTheme.fg(scheme))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(AppTheme.fg(scheme).opacity(0.08)))
                    }
                }

                Spacer()

                if spotifyAuth.isConnected {
                    Button("Disconnect", role: .destructive) {
                        spotifyAuth.disconnect()
                        if model.activeSource == .spotify {
                            model.selectMusicSource(.appleMusic)
                        }
                    }
                    .font(.system(size: 13, weight: .medium))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(AppTheme.fg(scheme).opacity(0.02)))
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
                        iconCircle(currentAppearanceMode == .dark
                                   ? "moon.fill"
                                   : currentAppearanceMode == .light ? "sun.max.fill" : "circle.lefthalf.filled")
                        Text("Appearance").gLabel()
                        Text(currentAppearanceMode.shortLabel).gValue(scheme)
                        Image(systemName: "chevron.right").gChevron()
                    }
                }
                .buttonStyle(.plain)
            }
            Text("Dark keeps the night-drive look; Auto follows the device setting.")
                .gNote(scheme)
        }
    }

    // MARK: - Support & about (one grouping: feedback, rate, share, version)

    private var supportAndAboutSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Support & about")
            group {
                // Feedback (design chat-bubble mark).
                Button {
                    if let url = URL(string: "mailto:support@caraoke.app?subject=Caraoke%20feedback") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    gRow {
                        iconCircle("message.fill")
                        Text("Feedback").gLabel()
                        Image(systemName: "chevron.right").gChevron()
                    }
                }
                .buttonStyle(.plain)
                rowDivider()
                rateRow
                rowDivider()
                shareRow
                rowDivider()
                aboutRow
            }
        }
    }

    /// Rate on the App Store
    private var rateRow: some View {
        Button {
            if let url = URL(string: "https://apps.apple.com/app/id6742353139?action=write-review") {
                UIApplication.shared.open(url)
            }
        } label: {
            gRow {
                iconCircle("star.fill")
                Text("Rate Caraoke").gLabel()
                Image(systemName: "chevron.right").gChevron()
            }
        }
        .buttonStyle(.plain)
    }

    private var shareRow: some View {
        ShareLink(item: URL(string: "https://caraoke.app")!) {
            gRow {
                iconCircle("square.and.arrow.up")
                Text("Share with friends").gLabel()
                Image(systemName: "chevron.right").gChevron()
            }
        }
        .buttonStyle(.plain)
    }

    private var aboutRow: some View {
        gRow {
            BrandMark(tinted: true)
                .frame(width: 26, height: 26)
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
    @AppStorage(AppearanceSettings.storageKey) private var appearanceRaw: String = AppearanceMode.auto.rawValue
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    private var currentMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceRaw) ?? .auto
    }

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
                        withAnimation(.easeInOut(duration: 0.15)) {
                            appearanceRaw = m.rawValue
                            AppearanceSettings.mode = m
                        }
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
                            if currentMode == m {
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
        .preferredColorScheme(currentMode.colorScheme)
    }

    private func icon(for mode: AppearanceMode) -> String {
        switch mode {
        case .auto: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}