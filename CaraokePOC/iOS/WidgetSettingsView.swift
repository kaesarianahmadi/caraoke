import SwiftUI
import UIKit
import WidgetKit

/// Widget controls and live preview. The app and extension share the settings
/// through the App Group container.
///
/// This view is pushed as a NavigationLink destination (e.g. from
/// Settings → Display → Widgets), so it must not embed its own
/// NavigationStack. The preview only ever shows the real now-playing values:
/// when nothing is playing it says so instead of dressing up a fake track.
struct WidgetSettingsView: View {
    @ObservedObject var model: RideModeViewModel
    @State private var settings = SharedWidgetSettings()
    @State private var settingsLoaded = false
    @State private var showTips = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var theme: WidgetTheme { WidgetTheme(rawValue: settings.theme) ?? .artwork }
    private var coverStyle: WidgetCoverStyle { WidgetCoverStyle(rawValue: settings.coverStyle) ?? .vinyl }
    private var hasTrack: Bool { !model.trackTitle.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                previewSection
                themeSection.disabled(!settingsLoaded)
                tipsToggle
                if showTips { tips }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(AppTheme.bg(scheme).ignoresSafeArea())
        .navigationTitle("Widgets")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            settings = await SharedWidgetStore.readSettings()
            settingsLoaded = true
        }
    }

    // MARK: - Write-through bindings

    private func binding<T: Sendable>(_ keyPath: WritableKeyPath<SharedWidgetSettings, T>,
                                      update: @escaping @Sendable (inout SharedWidgetSettings, T) -> Void) -> Binding<T> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { value in
                settings[keyPath: keyPath] = value
                SharedWidgetStore.updateSettings(reloadReason: "settings-changed") { update(&$0, value) }
            }
        )
    }

    // MARK: - Preview (real now-playing values only — never fake lyrics)

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(AppTheme.muted(scheme))
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            Group {
                if hasTrack || !model.currentLine.isEmpty {
                    livePreview
                } else {
                    emptyPreview
                }
            }
        }
    }

    private var livePreview: some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 0) {
                Text(identity)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.mutedTextColor)
                    .lineLimit(1)
                Spacer()
                Text(model.currentLine)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(theme.textColor)
                    .lineLimit(3)
                    .minimumScaleFactor(0.75)
                    .fixedSize(horizontal: false, vertical: true)
                if let next = model.nextLine, !next.isEmpty {
                    Text(next)
                        .font(.system(size: 15))
                        .foregroundStyle(theme.mutedTextColor.opacity(0.72))
                        .lineLimit(1)
                        .padding(.top, 3)
                }
                Spacer()
                HStack(spacing: 18) {
                    Image(systemName: "backward.fill")
                        .frame(width: 30, height: 30)
                    Image(systemName: model.isPlaybackActive ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 30, height: 30)
                    Image(systemName: "forward.fill")
                        .frame(width: 30, height: 30)
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            previewCover
                .frame(width: 132)
        }
        .padding(14)
        .frame(height: 160)
        .background(previewBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        .accessibilityLabel("Widget preview showing \(identity)")
    }

    /// Clean empty state: no invented track, no sample lyrics.
    private var emptyPreview: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note")
                .font(.title2.weight(.semibold))
                .foregroundColor(AppTheme.muted(scheme))
            Text("Nothing playing")
                .font(.body.weight(.semibold))
                .foregroundColor(AppTheme.fg(scheme))
            Text("The preview follows what is actually playing. Start a song in your music app and this card fills with its real lyrics.")
                .font(.subheadline)
                .foregroundColor(AppTheme.muted(scheme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(AppTheme.surface(scheme)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(AppTheme.border(scheme), lineWidth: 1))
        .accessibilityLabel("Widget preview is empty. No song is currently playing.")
    }

    private var identity: String {
        model.trackArtist.isEmpty ? model.trackTitle : "\(model.trackTitle) — \(model.trackArtist)"
    }

    @ViewBuilder private var previewCover: some View {
        if coverStyle == .vinyl {
            VinylRecordView(artworkData: model.artworkData, diameter: 126, labelDiameter: 88)
                .vinylSpin(model.isPlaybackActive && !reduceMotion)
        } else {
            CoverArtworkView(artworkData: model.artworkData, cornerRadius: 14,
                             artworkColorHex: model.artworkColorHex)
                .frame(width: 110, height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.12)))
        }
    }

    private var previewBackground: AnyShapeStyle {
        if theme == .artwork, let image = model.artworkData.flatMap(UIImage.init(data:)),
           let hex = image.averageColorHex, let color = Color(hexString: hex) {
            return AnyShapeStyle(LinearGradient(colors: [color.opacity(0.92), color.opacity(0.52), .black.opacity(0.9)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        return AnyShapeStyle(theme.backgroundColor)
    }

    // MARK: - Theme controls

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Theme")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(AppTheme.muted(scheme))
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                HStack {
                    Text("Theme")
                        .font(.body)
                        .foregroundColor(AppTheme.fg(scheme))
                    Spacer()
                    Picker("Theme", selection: binding(\.theme) { $0.theme = $1 }) {
                        ForEach(WidgetTheme.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(AppTheme.accent(scheme))
                    .accessibilityLabel("Widget theme")
                    .accessibilityValue(theme.displayName)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .frame(minHeight: 52, alignment: .leading)
                divider
                HStack {
                    Text("Cover style")
                        .font(.body)
                        .foregroundColor(AppTheme.fg(scheme))
                    Spacer()
                    Picker("Cover style", selection: binding(\.coverStyle) { $0.coverStyle = $1 }) {
                        ForEach(WidgetCoverStyle.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(AppTheme.accent(scheme))
                    .accessibilityLabel("Widget cover style")
                    .accessibilityValue(coverStyle.displayName)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .frame(minHeight: 52, alignment: .leading)
            }
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.surface(scheme)))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.border(scheme), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private var tipsToggle: some View {
        Button(showTips ? "Hide widget setup tips" : "Widget setup and update tips") {
            withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.2)) { showTips.toggle() }
        }
        .font(.headline.weight(.semibold))
        .foregroundStyle(AppTheme.accent(scheme))
        .frame(maxWidth: .infinity)
        .frame(minHeight: 44)
        .padding(.vertical, 15)
        .background(AppTheme.surface(scheme), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityHint(showTips ? "Hide widget update tips" : "Show widget update tips")
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tips")
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppTheme.muted(scheme))
            Text("1  How to add widgets:")
                .font(.headline.weight(.semibold))
            Text("Press and hold a blank area on the Home Screen, tap Edit, then Add Widget and choose Caraoke.")
            Text("2  Keep lyrics up to date:")
                .font(.headline.weight(.semibold))
            Text("Song changes update automatically. Tap the cover whenever the widget needs to resync.")
            Text("3  StandBy:")
                .font(.headline.weight(.semibold))
            Text("Place iPhone horizontally on a charger, then select the Caraoke lyrics widget.")
        }
        .font(.subheadline)
        .foregroundStyle(AppTheme.fg(scheme))
        .padding(.bottom, 20)
    }

    private var divider: some View { Divider().padding(.leading, 16) }
}
