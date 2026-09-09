import SwiftUI

/// Widget configuration screen (references IMG_5123, 5126, 5127, 5128):
/// - Live Widget Preview (Small / Medium / Large)
/// - Theme Picker (Pitch Black / Simple Slate / Ivory White)
/// - Cover Art Style (Picture / Vinyl Disc)
/// - StandBy Mode instructions
struct WidgetSettingsView: View {
    @AppStorage("widget_selected_theme") private var savedTheme: String = WidgetTheme.pitchBlack.rawValue
    @AppStorage("widget_selected_cover_style") private var savedCoverStyle: String = WidgetCoverStyle.picture.rawValue
    @State private var previewFamily: String = "Medium"
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    private var currentTheme: WidgetTheme {
        WidgetTheme(rawValue: savedTheme) ?? .pitchBlack
    }

    private var currentCoverStyle: WidgetCoverStyle {
        WidgetCoverStyle(rawValue: savedCoverStyle) ?? .picture
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.bg(scheme).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        previewSection
                        themeSection
                        coverStyleSection
                        standbySection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Widget Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(AppTheme.fg(scheme))
                }
            }
        }
    }

    // MARK: - Preview Section

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("PREVIEW")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.muted(scheme))
                Spacer()
                Picker("Size", selection: $previewFamily) {
                    Text("Small").tag("Small")
                    Text("Medium").tag("Medium")
                    Text("Large").tag("Large")
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(currentTheme.backgroundColor)
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 3)

                VStack(alignment: .center, spacing: 6) {
                    HStack(spacing: 8) {
                        if currentCoverStyle == .vinyl {
                            ZStack {
                                Circle().fill(Color.black).frame(width: 24, height: 24)
                                Circle().stroke(Color.white.opacity(0.3), lineWidth: 1).frame(width: 16, height: 16)
                                Circle().fill(Color(hex: 0xFF9845)).frame(width: 8, height: 8)
                            }
                        } else {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 22, height: 22)
                                .overlay(Image(systemName: "music.note").font(.system(size: 10)).foregroundColor(.white))
                        }
                        Text("Cruel Summer — Taylor Swift")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(currentTheme.textColor)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(currentTheme.mutedTextColor)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)

                    Spacer(minLength: 4)

                    VStack(alignment: .center, spacing: 4) {
                        Text("Fever dream high in the quiet of the night")
                            .font(.system(size: 12))
                            .foregroundColor(currentTheme.mutedTextColor.opacity(0.6))
                            .lineLimit(1)

                        Text("You know that I caught it")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(currentTheme.textColor)
                            .lineLimit(1)

                        Text("Bad, bad boy, shiny toy with a price")
                            .font(.system(size: 12))
                            .foregroundColor(currentTheme.mutedTextColor.opacity(0.7))
                            .lineLimit(1)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)

                    Spacer(minLength: 8)
                }
            }
            .frame(height: previewFamily == "Small" ? 140 : (previewFamily == "Large" ? 260 : 160))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(AppTheme.border(scheme), lineWidth: 1)
            )
        }
    }

    // MARK: - Theme Section

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("THEME")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.muted(scheme))

            VStack(spacing: 0) {
                ForEach(WidgetTheme.allCases, id: \.self) { theme in
                    Button {
                        savedTheme = theme.rawValue
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(theme.backgroundColor)
                                .frame(width: 24, height: 24)
                                .overlay(Circle().stroke(AppTheme.border(scheme), lineWidth: 1))

                            Text(theme.rawValue)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(AppTheme.fg(scheme))

                            Spacer()

                            if currentTheme == theme {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(AppTheme.ok)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)

                    if theme != WidgetTheme.allCases.last {
                        Divider().overlay(AppTheme.border(scheme))
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(AppTheme.surface(scheme)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppTheme.border(scheme), lineWidth: 1))
        }
    }

    // MARK: - Cover Art Style

    private var coverStyleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("COVER ART STYLE")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.muted(scheme))

            VStack(spacing: 0) {
                ForEach(WidgetCoverStyle.allCases, id: \.self) { style in
                    Button {
                        savedCoverStyle = style.rawValue
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: style == .picture ? "photo.fill" : "opticaldisc")
                                .font(.system(size: 18))
                                .foregroundColor(AppTheme.fg(scheme))
                                .frame(width: 24)

                            Text(style.rawValue)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(AppTheme.fg(scheme))

                            Spacer()

                            if currentCoverStyle == style {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(AppTheme.ok)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)

                    if style != WidgetCoverStyle.allCases.last {
                        Divider().overlay(AppTheme.border(scheme))
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(AppTheme.surface(scheme)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppTheme.border(scheme), lineWidth: 1))
        }
    }

    // MARK: - StandBy Mode Info

    private var standbySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("STANDBY MODE & TIPS")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.muted(scheme))

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 20))
                        .foregroundColor(Color(hex: 0xFFB800))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Supports iOS StandBy")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppTheme.fg(scheme))
                        Text("Place your iPhone horizontally on a charger to display Caraoke lyrics automatically.")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.muted(scheme))
                    }
                }

                Divider().overlay(AppTheme.border(scheme)).padding(.vertical, 4)

                HStack(spacing: 12) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 20))
                        .foregroundColor(AppTheme.ok)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tap Album Art to Resync")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppTheme.fg(scheme))
                        Text("Tapping the artwork refreshes the timeline instantly. Tapping lyrics opens Caraoke.")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.muted(scheme))
                    }
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(AppTheme.surface(scheme)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppTheme.border(scheme), lineWidth: 1))
        }
    }
}
