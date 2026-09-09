import SwiftUI
import UIKit
import WidgetKit

/// Widget controls and live preview. Every toggle writes to the shared
/// keychain store the widget extension reads, then asks WidgetKit to rebuild
/// — build 38 wrote these to an App Group container the extension has no
/// entitlement for, so none of them ever reached the widget.
struct WidgetSettingsView: View {
    @ObservedObject var model: RideModeViewModel
    @State private var settings = SharedWidgetStore.readSettings()
    @State private var showTips = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    private var theme: WidgetTheme { WidgetTheme(rawValue: settings.theme) ?? .artwork }
    private var coverStyle: WidgetCoverStyle { WidgetCoverStyle(rawValue: settings.coverStyle) ?? .vinyl }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    widgetPreview
                    settingsGroup
                    themeGroup
                    Button(showTips ? "Hide real-time update tips" : "Make widgets update in real time") {
                        withAnimation(.easeInOut(duration: 0.2)) { showTips.toggle() }
                    }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.accent(scheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(AppTheme.surface(scheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    if showTips {
                        tips
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(AppTheme.bg(scheme).ignoresSafeArea())
            .navigationTitle("Widget")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 40, height: 40)
                            .background(AppTheme.surface(scheme), in: Circle())
                    }
                    .accessibilityLabel("Back")
                }
            }
        }
    }

    // MARK: - Write-through bindings

    private func binding<T>(_ keyPath: WritableKeyPath<SharedWidgetSettings, T>) -> Binding<T> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { value in update { $0[keyPath: keyPath] = value } }
        )
    }

    /// Persist to the shared store and rebuild the widget timeline.
    private func update(_ mutate: (inout SharedWidgetSettings) -> Void) {
        mutate(&settings)
        SharedWidgetStore.writeSettings(settings)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Preview (mirrors the real medium widget)

    private var widgetPreview: some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 0) {
                Text(identity)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.mutedTextColor)
                    .lineLimit(1)
                Spacer()
                if settings.showLyrics {
                    Text(previousLine)
                        .font(.system(size: 15))
                        .foregroundStyle(theme.mutedTextColor.opacity(0.5))
                        .lineLimit(1)
                        .padding(.bottom, 3)
                    Text(heroLine)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(theme.textColor)
                        .lineLimit(3)
                        .minimumScaleFactor(0.75)
                    if settings.showTranslation, let translation = model.currentTranslation, !translation.isEmpty {
                        Text(translation)
                            .font(.system(size: 12))
                            .foregroundStyle(theme.mutedTextColor.opacity(0.8))
                            .lineLimit(2)
                            .padding(.top, 2)
                    }
                    Text(nextLine)
                        .font(.system(size: 15))
                        .foregroundStyle(theme.mutedTextColor.opacity(0.72))
                        .lineLimit(1)
                        .padding(.top, 3)
                }
                Spacer()
                HStack(spacing: 18) {
                    Image(systemName: "backward.fill")
                    Image(systemName: model.isPlaybackActive ? "pause.fill" : "play.fill")
                    Image(systemName: "forward.fill")
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
        .background(previewBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
    }

    private var identity: String {
        guard !model.trackTitle.isEmpty else { return "Do You Like Me? — Daniel Caesar" }
        return model.trackArtist.isEmpty ? model.trackTitle : "\(model.trackTitle) — \(model.trackArtist)"
    }

    private var heroLine: String {
        model.currentLine.isEmpty ? "Do you like the way I talk to you?" : model.currentLine
    }

    private var previousLine: String {
        model.previousLines.last ?? "Do I titillate your mind?"
    }

    private var nextLine: String {
        model.nextLine ?? "And I'd love to make you mine"
    }

    @ViewBuilder private var previewCover: some View {
        ZStack(alignment: .topTrailing) {
            if coverStyle == .vinyl {
                ZStack {
                    Circle().fill(RadialGradient(colors: [.black, Color(white: 0.17), .black], center: .center, startRadius: 6, endRadius: 64))
                    ForEach(0..<6, id: \.self) { index in
                        Circle().stroke(.white.opacity(0.08), lineWidth: 0.5).padding(CGFloat(index * 8 + 6))
                    }
                    coverLabel
                        .frame(width: 88, height: 88)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(.white.opacity(0.15)))
                    Circle().fill(.white.opacity(0.5)).frame(width: 7, height: 7)
                }
                .frame(width: 126, height: 126)
            } else {
                coverLabel
                    .frame(width: 110, height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.12)))
            }
            if settings.showRefresh {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.34), in: Circle())
            }
        }
    }

    @ViewBuilder private var coverLabel: some View {
        if let data = model.artworkData, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            LinearGradient(colors: [Color(hex: 0x9E6752), Color(hex: 0x27304D)], startPoint: .top, endPoint: .bottom)
                .overlay(Image(systemName: "music.note").font(.title).foregroundStyle(.white.opacity(0.8)))
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

    // MARK: - Groups

    private var settingsGroup: some View {
        section(title: "Widget settings") {
            toggleRow("Show lyrics", isOn: binding(\.showLyrics))
            divider
            toggleRow("Show refresh button", isOn: binding(\.showRefresh))
            divider
            toggleRow("Show translation (if available)", isOn: binding(\.showTranslation))
        }
    }

    private var themeGroup: some View {
        section(title: "Theme settings") {
            HStack {
                Text("Theme")
                Spacer()
                ForEach(WidgetTheme.allCases, id: \.self) { item in
                    Button { update { $0.theme = item.rawValue } } label: {
                        Circle()
                            .fill(item.backgroundColor)
                            .frame(width: 28, height: 28)
                            .overlay(Circle().stroke(item == theme ? AppTheme.accent(scheme) : AppTheme.border(scheme),
                                                     lineWidth: item == theme ? 3 : 1))
                    }
                    .accessibilityLabel(item.displayName)
                }
            }
            .padding(16)
            divider
            HStack {
                Text("Cover style")
                Spacer()
                Picker("Cover style", selection: binding(\.coverStyle)) {
                    ForEach(WidgetCoverStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 190)
            }
            .padding(16)
        }
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tips").font(.system(size: 15, weight: .semibold)).foregroundStyle(AppTheme.muted(scheme))
            Text("1  How to add widgets:").font(.system(size: 16, weight: .semibold))
            Text("Press and hold a blank area on the Home Screen, tap Edit, then Add Widget and choose Caraoke.")
            Text("2  Keep lyrics up to date:").font(.system(size: 16, weight: .semibold))
            Text("Song changes update automatically. Tap the cover or refresh button whenever the widget needs to resync.")
            Text("3  StandBy:").font(.system(size: 16, weight: .semibold))
            Text("Place iPhone horizontally on a charger, then select the Caraoke lyrics widget.")
        }
        .font(.system(size: 14))
        .foregroundStyle(AppTheme.fg(scheme))
        .padding(.bottom, 20)
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 15, weight: .semibold))
            VStack(spacing: 0, content: content)
                .background(AppTheme.surface(scheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title).font(.system(size: 15))
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(AppTheme.ok)
        }
        .padding(.horizontal, 16).frame(minHeight: 52)
    }

    private var divider: some View { Divider().padding(.leading, 16) }
}
