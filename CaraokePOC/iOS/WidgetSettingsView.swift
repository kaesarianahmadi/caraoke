import SwiftUI

/// Widget controls and live competitor-style preview.
struct WidgetSettingsView: View {
    @AppStorage("widget_selected_theme", store: UserDefaults(suiteName: "group.app.caraoke")) private var savedTheme = WidgetTheme.artwork.rawValue
    @AppStorage("widget_selected_cover_style", store: UserDefaults(suiteName: "group.app.caraoke")) private var savedCoverStyle = WidgetCoverStyle.vinyl.rawValue
    @AppStorage("widget_show_lyrics", store: UserDefaults(suiteName: "group.app.caraoke")) private var showLyrics = true
    @AppStorage("widget_show_refresh", store: UserDefaults(suiteName: "group.app.caraoke")) private var showRefresh = true
    @AppStorage("widget_show_translation", store: UserDefaults(suiteName: "group.app.caraoke")) private var showTranslation = false
    @State private var showTips = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    private var theme: WidgetTheme { WidgetTheme(rawValue: savedTheme) ?? .artwork }
    private var coverStyle: WidgetCoverStyle { WidgetCoverStyle(rawValue: savedCoverStyle) ?? .vinyl }

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
                        .foregroundStyle(.blue)
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

    private var widgetPreview: some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Do You Like Me? — Daniel Caesar")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.mutedTextColor)
                    .lineLimit(1)
                Spacer()
                if showLyrics {
                    Text("Do I titillate your mind?")
                        .font(.system(size: 15))
                        .foregroundStyle(theme.mutedTextColor.opacity(0.5))
                        .lineLimit(1)
                        .padding(.bottom, 3)
                    Text("Do you like the way I talk to you?")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(theme.textColor)
                        .lineLimit(2)
                    Text(showTranslation ? "Apakah kamu suka caraku bicara?" : "And I'd love to make you mine")
                        .font(.system(size: 15))
                        .foregroundStyle(theme.mutedTextColor.opacity(0.72))
                        .lineLimit(1)
                        .padding(.top, 3)
                }
                Spacer()
                HStack(spacing: 18) {
                    Image(systemName: "backward.fill")
                    Image(systemName: "pause.fill")
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

    @ViewBuilder private var previewCover: some View {
        ZStack(alignment: .topTrailing) {
            if coverStyle == .vinyl {
                ZStack {
                    Circle().fill(RadialGradient(colors: [.black, Color(white: 0.17), .black], center: .center, startRadius: 6, endRadius: 64))
                    ForEach(0..<6, id: \.self) { index in
                        Circle().stroke(.white.opacity(0.08), lineWidth: 0.5).padding(CGFloat(index * 8 + 6))
                    }
                    Circle().fill(Color(hex: 0x9E6752)).frame(width: 76, height: 76)
                    Circle().fill(.white.opacity(0.5)).frame(width: 7, height: 7)
                }
                .frame(width: 126, height: 126)
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x9E6752), Color(hex: 0x27304D)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 110, height: 110)
                    .overlay(Image(systemName: "music.note").font(.title).foregroundStyle(.white.opacity(0.8)))
            }
            if showRefresh {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.34), in: Circle())
            }
        }
    }

    private var previewBackground: AnyShapeStyle {
        theme == .artwork
            ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x455B79), Color(hex: 0x192337), .black],
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
            : AnyShapeStyle(theme.backgroundColor)
    }

    private var settingsGroup: some View {
        section(title: "Widget Setting") {
            toggleRow("Show lyrics", isOn: $showLyrics, badge: "Free try")
            divider
            toggleRow("Show refresh button", isOn: $showRefresh)
            divider
            toggleRow("Show translation (if available)", isOn: $showTranslation)
        }
    }

    private var themeGroup: some View {
        section(title: "Theme settings", badge: "Premium") {
            HStack {
                Text("Theme")
                Spacer()
                ForEach(WidgetTheme.allCases, id: \.self) { item in
                    Button { savedTheme = item.rawValue } label: {
                        Circle()
                            .fill(item.backgroundColor)
                            .frame(width: 28, height: 28)
                            .overlay(Circle().stroke(item == theme ? Color.blue : AppTheme.border(scheme), lineWidth: item == theme ? 3 : 1))
                    }
                    .accessibilityLabel(item.rawValue)
                }
            }
            .padding(16)
            divider
            HStack {
                Text("Cover style")
                Spacer()
                Picker("Cover style", selection: $savedCoverStyle) {
                    Text("Vinyl").tag(WidgetCoverStyle.vinyl.rawValue)
                    Text("Picture").tag(WidgetCoverStyle.picture.rawValue)
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
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

    private func section<Content: View>(title: String, badge: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(size: 15, weight: .semibold))
                if let badge {
                    Text(badge).font(.system(size: 11, weight: .bold)).foregroundStyle(.blue)
                        .padding(.horizontal, 7).padding(.vertical, 3).background(.blue.opacity(0.14), in: Capsule())
                }
            }
            VStack(spacing: 0, content: content)
                .background(AppTheme.surface(scheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>, badge: String? = nil) -> some View {
        HStack {
            Text(title).font(.system(size: 15))
            if let badge {
                Text(badge).font(.system(size: 11, weight: .bold)).foregroundStyle(.blue)
                    .padding(.horizontal, 7).padding(.vertical, 3).background(.blue.opacity(0.14), in: Capsule())
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(.green)
        }
        .padding(.horizontal, 16).frame(minHeight: 52)
    }

    private var divider: some View { Divider().padding(.leading, 16) }
}
