import SwiftUI
import UIKit

/// Settings screen.
/// Sections (top to bottom): Music connections, Display (appearance, lyric
/// bold text, Widgets destination), Caraoke Plus (subscription entry),
/// Support, Help & About. Pushed by the root navigation, so this screen
/// carries no NavigationStack of its own; the Widgets and Help rows are
/// NavigationLinks inside the shared stack. Spotify's connection flow lives
/// in `SpotifySetupView`; this screen only opens it as a sheet.
struct SettingsView: View {
    @ObservedObject var model: RideModeViewModel
    var presentingPaywall: Binding<Bool>
    /// Shared auth — the same object the playback pipeline uses (injected by
    /// the VM), so connecting here connects the pipeline and vice versa.
    @ObservedObject var spotifyAuth: SpotifyAuth
    @State private var showAppearanceSheet = false
    @State private var showSpotifySetup = false
    @State private var showOnboarding = false
    @AppStorage(AppearanceSettings.storageKey) private var appearanceRaw: String = AppearanceMode.auto.rawValue
    @AppStorage(AppearanceSettings.boldTextKey) private var boldText = true
    @Environment(\.colorScheme) private var scheme

    private var currentAppearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceRaw) ?? .auto
    }

    var body: some View {
        ZStack {
            AppTheme.background(scheme)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    musicConnectionsSection
                    displaySection
                    caraokePlusSection
                    supportHelpAboutSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .tint(AppTheme.accent(scheme))
        .preferredColorScheme(currentAppearanceMode.colorScheme)
        .onChange(of: spotifyAuth.isConnected) { _, connected in
            if !connected, model.activeSource == .spotify {
                model.selectMusicSource(.appleMusic)
            }
        }
        .sheet(isPresented: $showAppearanceSheet) {
            AppearanceSheet()
                .preferredColorScheme(currentAppearanceMode.colorScheme)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSpotifySetup) {
            SpotifySetupView(spotifyAuth: spotifyAuth, onConnected: {
                model.selectMusicSource(.spotify)
            })
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(onDismiss: { showOnboarding = false })
                .preferredColorScheme(currentAppearanceMode.colorScheme)
                .presentationDetents([.large])
        }
    }

    // MARK: - Design primitives

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(AppTheme.muted(scheme))
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
            .accessibilityAddTraits(.isHeader)
    }

    private func group<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.surface(scheme)))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.border(scheme), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func rowDivider() -> some View {
        Divider().overlay(AppTheme.border(scheme))
    }

    /// Plain neutral row symbol — no colored tile. Orange is reserved for
    /// selected controls and actions, not a decoration on every icon.
    private func rowIcon(_ systemName: String, active: Bool = false) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(active ? AppTheme.accent(scheme) : AppTheme.muted(scheme))
            .frame(width: 28, height: 28)
    }

    // MARK: - Caraoke Plus (subscription entry)

    private var caraokePlusSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Caraoke Plus")
            group {
                Button { presentingPaywall.wrappedValue = true } label: {
                    gRow {
                        rowIcon("star.fill")
                        Text("Plans & pricing").gLabel()
                        Text("View").gValue(scheme)
                        Image(systemName: "chevron.right").gChevron()
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Music connections

    private var musicConnectionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Music connections")
            group {
                appleMusicRow
                if FeatureFlags.spotifyEnabled {
                    rowDivider()
                    spotifyRow
                    if spotifyAuth.isConnected, !model.spotifyConnected {
                        rowDivider()
                        makeActiveRow
                    }
                }
            }
        }
    }

    private var appleMusicRow: some View {
        Button {
            model.selectMusicSource(.appleMusic)
        } label: {
            gRow {
                AppleMusicLogo().frame(width: 28, height: 28)
                Text("Apple Music").gLabel()
                Text(model.appleMusicConnected ? "Active source" : "Standby")
                    .font(.subheadline.weight(.medium))
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

    /// Tapping the row opens the Spotify connection sheet (connect /
    /// reconnect / disconnect); connecting there also makes Spotify the
    /// active source via `onConnected`.
    private var spotifyRow: some View {
        Button { showSpotifySetup = true } label: {
            gRow {
                SpotifyLogo(size: 28).frame(width: 28, height: 28)
                Text("Spotify").gLabel()
                if model.spotifyConnected {
                    Text("Active source")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(AppTheme.ok)
                } else if spotifyAuth.needsReconnect {
                    Text("Reconnect needed")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(AppTheme.warn)
                } else if spotifyAuth.isConnected {
                    Text("Connected (Standby)")
                        .font(.subheadline)
                        .foregroundColor(AppTheme.muted(scheme))
                } else {
                    Text("Not connected")
                        .font(.subheadline)
                        .foregroundColor(AppTheme.warn)
                        .accessibilityHint("Open Spotify connection setup")
                }
                if model.spotifyConnected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.ok)
                } else {
                    Image(systemName: "chevron.right").gChevron()
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// Connected but not active: one tap picks Spotify without reopening
    /// the connection flow.
    private var makeActiveRow: some View {
        Button {
            model.selectMusicSource(.spotify)
        } label: {
            HStack {
                Text("Make Spotify the active source")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppTheme.accent(scheme))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Switch now-playing to Spotify")
    }

    // MARK: - Display (appearance, lyric bold text, Widgets destination)

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Display")
            group {
                Button {
                    showAppearanceSheet = true
                } label: {
                    gRow {
                        rowIcon(currentAppearanceMode == .dark
                            ? "moon.fill"
                            : currentAppearanceMode == .light ? "sun.max.fill" : "circle.lefthalf.filled")
                        Text("Appearance").gLabel()
                        Text(currentAppearanceMode.shortLabel).gValue(scheme)
                        Image(systemName: "chevron.right").gChevron()
                    }
                }
                .buttonStyle(.plain)
                rowDivider()
                // Bold Text switch. The faces everywhere are already bold, so
                // this steps them down to plain when the user wants lighter
                // type (and whenever iOS Bold Text itself is on).
                gRow {
                    rowIcon("bold")
                    Text("Bold Text").gLabel()
                    Toggle("Bold Text", isOn: $boldText)
                        .labelsHidden()
                        .tint(AppTheme.accent(scheme))
                }
                .frame(minHeight: 52)
                rowDivider()
                NavigationLink {
                    WidgetSettingsView(model: model)
                } label: {
                    gRow {
                        rowIcon("widget.small")
                        Text("Widgets").gLabel()
                        Image(systemName: "chevron.right").gChevron()
                    }
                }
                .accessibilityHint("Opens widget themes, cover style and previews")
            }
            Text("Dark keeps the night-drive look; Auto follows the device setting. Bold Text off renders lyrics and titles at regular weight. Widgets show live lyrics on your Home Screen and StandBy.")
                .gNote(scheme)
        }
    }

    // MARK: - Support, Help & About

    private var supportHelpAboutSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Support, Help & About")
            group {
                NavigationLink {
                    HelpView()
                } label: {
                    gRow {
                        rowIcon("questionmark")
                        Text("Help & setup").gLabel()
                        Image(systemName: "chevron.right").gChevron()
                    }
                }
                .accessibilityHint("Opens the offline setup and troubleshooting guide")
                rowDivider()
                Button { showOnboarding = true } label: {
                    gRow {
                        rowIcon("sparkles")
                        Text("Welcome guide").gLabel()
                        Image(systemName: "chevron.right").gChevron()
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Replay the three-step welcome guide")
                rowDivider()
                Button {
                    if let url = URL(string: "mailto:support@caraoke.app?subject=Caraoke%20feedback") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    gRow {
                        rowIcon("message.fill")
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
            HStack(spacing: 10) {
                Link("Privacy Policy", destination: URL(string: "https://caraokeapp.com/privacy")!)
                    .foregroundColor(AppTheme.accent(scheme))
                    .frame(minHeight: 44)
                Text("·")
                    .foregroundColor(AppTheme.muted(scheme))
                Link("Terms of Use", destination: URL(string: "https://caraokeapp.com/terms")!)
                    .foregroundColor(AppTheme.accent(scheme))
                    .frame(minHeight: 44)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 4)
            .padding(.top, 4)
        }
    }

    private var rateRow: some View {
        Button {
            if let url = URL(string: "https://apps.apple.com/app/id6742353139?action=write-review") {
                UIApplication.shared.open(url)
            }
        } label: {
            gRow {
                rowIcon("star.fill")
                Text("Rate Caraoke").gLabel()
                Image(systemName: "chevron.right").gChevron()
            }
        }
        .buttonStyle(.plain)
    }

    private var shareRow: some View {
        ShareLink(item: URL(string: "https://caraoke.app")!) {
            gRow {
                rowIcon("square.and.arrow.up")
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Caraoke version \(versionText)")
    }

    private var footnote: some View {
        Text("Caraoke \(versionText) · Made for passengers · Lyrics © their respective rights holders")
            .font(.caption2)
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
            .font(.body)
            .foregroundColor(AppTheme.fg(scheme))
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
    }
}

private struct GChevronModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .font(.subheadline.weight(.semibold))
            .foregroundColor(AppTheme.muted(scheme))
    }
}

private extension View {
    /// `.g-label` — primary row label.
    func gLabel() -> some View { modifier(GLabelModifier()) }

    /// `.g-value` — muted trailing value.
    func gValue(_ scheme: ColorScheme) -> some View {
        font(.body)
            .foregroundColor(AppTheme.muted(scheme))
    }

    /// `.g-chev` — chevron built from the SF Symbol.
    func gChevron() -> some View { modifier(GChevronModifier()) }

    /// `.g-note` — muted note under a group.
    func gNote(_ scheme: ColorScheme) -> some View {
        font(.subheadline)
            .foregroundColor(AppTheme.muted(scheme))
            .padding(.horizontal, 4)
            .padding(.top, 8)
    }
}

// MARK: - Appearance bottom sheet

struct AppearanceSheet: View {
    @AppStorage(AppearanceSettings.storageKey) private var appearanceRaw: String = AppearanceMode.auto.rawValue
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var currentMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceRaw) ?? .auto
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Appearance")
                    .font(.headline)
                    .foregroundColor(AppTheme.fg(scheme))
                Spacer()
                Button("Done") { dismiss() }
                    .font(.headline.weight(.medium))
                    .foregroundColor(AppTheme.accent(scheme))
                    .frame(minHeight: 44)
            }
            VStack(spacing: 0) {
                ForEach(AppearanceMode.allCases) { m in
                    Button {
                        withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.15)) {
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
                            .frame(width: 28, height: 28)
                            Text(m.sheetLabel)
                                .font(.body)
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
                        .frame(minHeight: 52, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(currentMode == m ? "Selected" : "")
                }
            }
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.surface(scheme)))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.border(scheme), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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
