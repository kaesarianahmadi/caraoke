import SwiftUI

/// Unified Surface Studio (Widgets, CarPlay Stack, Lock Screen & Dynamic Island).
struct WidgetSettingsView: View {
    var model: RideModeViewModel? = nil

    enum SurfaceFamily: String, CaseIterable, Identifiable {
        case widget = "Widget (2×4)"
        case carPlay = "CarPlay Stack"
        case lockIsland = "Lock & Island"
        var id: String { rawValue }
    }

    @State private var family: SurfaceFamily = .widget
    @AppStorage("widget.theme") private var themeRaw = WidgetTheme.artwork.rawValue
    @AppStorage("widget.coverStyle") private var coverRaw = WidgetCoverStyle.vinyl.rawValue
    @State private var offsetMs: Int = 0
    @State private var showHelp = false
    @Environment(\.colorScheme) private var scheme

    private var theme: WidgetTheme { WidgetTheme(rawValue: themeRaw) ?? .artwork }
    private var coverStyle: WidgetCoverStyle { WidgetCoverStyle(rawValue: coverRaw) ?? .vinyl }

    var body: some View {
        ZStack {
            AppTheme.bg(scheme).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    Picker("Surface", selection: $family) {
                        ForEach(SurfaceFamily.allCases) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)

                    // Pinned Live Preview Well
                    ZStack {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: 0x16161A), Color(hex: 0x0A0A0C)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        previewCard
                            .padding(16)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(AppTheme.border(scheme), lineWidth: 1)
                    )

                    // Tactile Circular Theme Swatches
                    VStack(alignment: .leading, spacing: 10) {
                        Text("THEME")
                            .font(.caption.weight(.bold))
                            .foregroundColor(AppTheme.muted(scheme))
                            .padding(.leading, 4)

                        HStack(spacing: 0) {
                            ForEach(WidgetTheme.allCases, id: \.rawValue) { item in
                                swatchButton(for: item)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 8)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(AppTheme.surface(scheme)))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AppTheme.border(scheme), lineWidth: 1))
                    }

                    // Cover Style & CarPlay Timing Offset
                    VStack(alignment: .leading, spacing: 10) {
                        Text("STYLE & TIMING")
                            .font(.caption.weight(.bold))
                            .foregroundColor(AppTheme.muted(scheme))
                            .padding(.leading, 4)

                        VStack(spacing: 0) {
                            HStack {
                                Text("Cover Style")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(AppTheme.fg(scheme))
                                Spacer()
                                Picker("Cover Style", selection: $coverRaw) {
                                    Text("Vinyl").tag(WidgetCoverStyle.vinyl.rawValue)
                                    Text("Square").tag(WidgetCoverStyle.picture.rawValue)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 150)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)

                            Divider().overlay(AppTheme.border(scheme))

                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("CarPlay Timing Offset")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(AppTheme.fg(scheme))
                                    Text("Compensates wireless Bluetooth lag")
                                        .font(.caption2)
                                        .foregroundColor(AppTheme.muted(scheme))
                                }
                                Spacer()
                                HStack(spacing: 8) {
                                    Button {
                                        updateOffset(offsetMs - 250)
                                    } label: {
                                        Image(systemName: "minus")
                                            .font(.caption.weight(.bold))
                                            .frame(width: 30, height: 30)
                                            .background(Circle().fill(AppTheme.surfaceElevated(scheme)))
                                    }
                                    Text(offsetLabel)
                                        .font(.subheadline.weight(.bold).monospacedDigit())
                                        .foregroundColor(AppTheme.accent(scheme))
                                        .frame(minWidth: 46)
                                    Button {
                                        updateOffset(offsetMs + 250)
                                    } label: {
                                        Image(systemName: "plus")
                                            .font(.caption.weight(.bold))
                                            .frame(width: 30, height: 30)
                                            .background(Circle().fill(AppTheme.surfaceElevated(scheme)))
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                        }
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(AppTheme.surface(scheme)))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AppTheme.border(scheme), lineWidth: 1))
                    }

                    Button {
                        showHelp = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(AppTheme.accent(scheme))
                            Text("How to add to CarPlay, Lock Screen & StandBy")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(AppTheme.fg(scheme))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundColor(AppTheme.muted(scheme))
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(AppTheme.surface(scheme)))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppTheme.border(scheme), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("Surface Studio")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            offsetMs = await SharedWidgetStore.readSettings().lyricOffsetMs
        }
        .onChange(of: themeRaw) { _, newValue in
            SharedWidgetStore.updateSettings { $0.theme = newValue }
        }
        .onChange(of: coverRaw) { _, newValue in
            SharedWidgetStore.updateSettings { $0.coverStyle = newValue }
        }
        .sheet(isPresented: $showHelp) {
            NavigationStack {
                HelpView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showHelp = false }
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private var previewCard: some View {
        let title = (model?.trackTitle.isEmpty == false) ? (model?.trackTitle ?? "Disillusioned") : "Disillusioned"
        let artist = (model?.trackArtist.isEmpty == false) ? (model?.trackArtist ?? "Daniel Caesar") : "Daniel Caesar"
        let line = (model?.currentLine.isEmpty == false) ? (model?.currentLine ?? "Maybe should get together") : "Maybe should get together"
        let next = model?.nextLine ?? "We'll take it all on better"

        switch family {
        case .widget:
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(title) — \(artist)")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(theme.mutedTextColor)
                        .lineLimit(1)
                    Text(line)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(theme.textColor)
                        .lineLimit(2)
                    Text(next)
                        .font(.system(size: 13))
                        .foregroundColor(theme.mutedTextColor)
                        .lineLimit(1)
                    HStack(spacing: 18) {
                        Image(systemName: "backward.fill")
                        Image(systemName: "pause.fill")
                        Image(systemName: "forward.fill")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(theme.textColor)
                    .padding(.top, 4)
                }
                Spacer(minLength: 4)
                if coverStyle == .vinyl {
                    VinylRecordView(artworkData: model?.artworkData, diameter: 82, labelDiameter: 50)
                        .vinylSpin(model?.isPlaybackActive ?? false)
                } else {
                    CoverArtworkView(artworkData: model?.artworkData, cornerRadius: 12, artworkColorHex: model?.artworkColorHex)
                        .frame(width: 78, height: 78)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(theme.backgroundColor)
            )

        case .carPlay:
            HStack(spacing: 10) {
                VStack(spacing: 8) {
                    CoverArtworkView(artworkData: model?.artworkData, cornerRadius: 10, artworkColorHex: model?.artworkColorHex)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Text(title)
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    HStack(spacing: 12) {
                        Image(systemName: "backward.fill")
                        Image(systemName: "pause.fill")
                        Image(systemName: "forward.fill")
                    }
                    .font(.caption2)
                    .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0x18181B)))

                VStack(alignment: .leading, spacing: 6) {
                    Text(line)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    Text(next)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Capsule()
                        .fill(AppTheme.darkAccent)
                        .frame(width: 52, height: 2.5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black))
            }

        case .lockIsland:
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform")
                            .foregroundColor(AppTheme.darkAccent)
                        Text(line)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(Capsule().fill(Color.black))

                    CoverArtworkView(artworkData: model?.artworkData, cornerRadius: 17, artworkColorHex: model?.artworkColorHex)
                        .frame(width: 34, height: 34)
                        .clipShape(Circle())
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(line)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    Text(next)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.65))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(CoverArtworkView.controlledStageWash(model?.artworkColorHex, enabled: true)
                              ?? LinearGradient(colors: [Color(hex: 0x202026), Color.black], startPoint: .top, endPoint: .bottom))
                )
            }
        }
    }

    private func swatchButton(for item: WidgetTheme) -> some View {
        let selected = theme == item
        return Button {
            themeRaw = item.rawValue
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(swatchFill(for: item))
                        .frame(width: 44, height: 44)
                        .overlay(Circle().stroke(Color.white.opacity(0.22), lineWidth: 1))
                    if item == .artwork {
                        Image(systemName: "paintpalette.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                    }
                }
                .padding(3)
                .overlay(
                    Circle().stroke(selected ? AppTheme.accent(scheme) : Color.clear, lineWidth: 2)
                )

                Text(swatchShortLabel(for: item))
                    .font(.caption2.weight(selected ? .bold : .medium))
                    .foregroundColor(selected ? AppTheme.fg(scheme) : AppTheme.muted(scheme))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.displayName) theme")
    }

    private func swatchFill(for item: WidgetTheme) -> LinearGradient {
        switch item {
        case .artwork:
            return LinearGradient(colors: [Color(hex: 0xFF9845), Color(hex: 0x4F46E5)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .pitchBlack:
            return LinearGradient(colors: [Color.black, Color(hex: 0x111113)], startPoint: .top, endPoint: .bottom)
        case .simpleSlate:
            return LinearGradient(colors: [Color(hex: 0x27272A), Color(hex: 0x18181B)], startPoint: .top, endPoint: .bottom)
        case .ivoryWhite:
            return LinearGradient(colors: [Color.white, Color(hex: 0xE4E4E7)], startPoint: .top, endPoint: .bottom)
        }
    }

    private func swatchShortLabel(for item: WidgetTheme) -> String {
        switch item {
        case .artwork: return "Cover"
        case .pitchBlack: return "OLED"
        case .simpleSlate: return "Slate"
        case .ivoryWhite: return "Ivory"
        }
    }

    private var offsetLabel: String {
        if offsetMs == 0 { return "0.0s" }
        return String(format: "%+.2gs", Double(offsetMs) / 1000.0)
    }

    private func updateOffset(_ raw: Int) {
        let clamped = max(-5000, min(5000, raw))
        let delta = clamped - offsetMs
        offsetMs = clamped
        if let model {
            model.adjustLyricOffset(by: delta)
        } else {
            SharedWidgetStore.updateSettings { $0.lyricOffsetMs = clamped }
        }
    }
}
