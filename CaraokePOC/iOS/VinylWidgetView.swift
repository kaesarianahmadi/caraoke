import AppIntents
import SwiftUI
import UIKit
import WidgetKit

/// Competitor-style medium widget: lyrics left, large record or cover right.
/// WidgetKit timeline transitions supply lyric motion; this view stays static
/// so manual refresh never flashes through an animation reset.
struct VinylWidgetView: View {
    let entry: CaraokeWidgetEntry

    @AppStorage("widget_selected_theme", store: UserDefaults(suiteName: "group.app.caraoke")) private var savedTheme = WidgetTheme.artwork.rawValue
    @AppStorage("widget_selected_cover_style", store: UserDefaults(suiteName: "group.app.caraoke")) private var savedCoverStyle = WidgetCoverStyle.vinyl.rawValue
    @AppStorage("widget_show_lyrics", store: UserDefaults(suiteName: "group.app.caraoke")) private var showLyrics = true
    @AppStorage("widget_show_refresh", store: UserDefaults(suiteName: "group.app.caraoke")) private var showRefresh = true

    private var theme: WidgetTheme { WidgetTheme(rawValue: savedTheme) ?? .artwork }
    private var coverStyle: WidgetCoverStyle { WidgetCoverStyle(rawValue: savedCoverStyle) ?? .vinyl }
    private var artwork: UIImage? { entry.artworkData.flatMap(UIImage.init(data:)) }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 4) {
                lyricsSection
                    .frame(width: geometry.size.width * 0.58, alignment: .leading)
                cover
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(14)
        }
        // Manual refresh swaps the entry date; the identity change fades the
        // whole card out and back in instead of blinking to a blank frame.
        .id(entry.date)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.45), value: entry.date)
        .foregroundStyle(theme.textColor)
        .containerBackground(for: .widget) { WidgetArtworkBackground(theme: theme, artworkData: entry.artworkData) }
        .widgetURL(URL(string: "caraoke://lyrics"))
    }

    private var lyricsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(identity)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.mutedTextColor)
                .lineLimit(1)

            Spacer(minLength: 5)

            if showLyrics {
                // Same size for every line; only the playing line is bold.
                VStack(alignment: .leading, spacing: 3) {
                    if let previous = entry.previousLines.last {
                        Text(previous)
                            .font(.system(size: 15))
                            .foregroundStyle(theme.mutedTextColor.opacity(0.55))
                            .lineLimit(1)
                    }
                    Text(entry.currentLine.isEmpty ? "Play a song to see lyrics" : entry.currentLine)
                        .font(.system(size: 15, weight: .bold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let next = entry.nextLine, !next.isEmpty {
                        Text(next)
                            .font(.system(size: 15))
                            .foregroundStyle(theme.mutedTextColor.opacity(0.72))
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 5)

            HStack(spacing: 16) {
                intentButton("backward.fill", intent: PreviousTrackIntent(), label: "Previous song", size: 14)
                intentButton(entry.isPlaying ? "pause.fill" : "play.fill", intent: PlayPauseIntent(), label: entry.isPlaying ? "Pause" : "Play", size: 17)
                intentButton("forward.fill", intent: NextTrackIntent(), label: "Next song", size: 14)
            }
        }
    }

    @ViewBuilder private var cover: some View {
        ZStack(alignment: .topTrailing) {
            if coverStyle == .vinyl {
                vinyl
            } else {
                Group {
                    if let artwork {
                        Image(uiImage: artwork).resizable().scaledToFill()
                    } else {
                        Rectangle().fill(.white.opacity(0.1)).overlay(Image(systemName: "music.note").font(.title2))
                    }
                }
                .frame(width: 110, height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.12)))
            }

            if showRefresh {
                Button(intent: ResyncWidgetIntent()) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 36, height: 36)
                        .background(.black.opacity(0.32), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh lyrics")
            }
        }
    }

    private var vinyl: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [.black, Color(white: 0.16), .black], center: .center, startRadius: 8, endRadius: 65))
            ForEach(0..<7, id: \.self) { index in
                Circle().stroke(.white.opacity(0.07), lineWidth: 0.5)
                    .padding(CGFloat(index * 7 + 5))
            }
            Group {
                if let artwork {
                    Image(uiImage: artwork).resizable().scaledToFill()
                } else {
                    Circle().fill(.gray.opacity(0.35)).overlay(Image(systemName: "music.note"))
                }
            }
            .frame(width: 76, height: 76)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white.opacity(0.15)))
            Circle().fill(.white.opacity(0.55)).frame(width: 7, height: 7)
        }
        .frame(width: 126, height: 126)
        .shadow(color: .black.opacity(0.28), radius: 7, y: 4)
    }

    private var identity: String {
        entry.artist.isEmpty ? entry.title : "\(entry.title) — \(entry.artist)"
    }

    private func intentButton<I: AppIntent>(_ name: String, intent: I, label: String, size: CGFloat) -> some View {
        Button(intent: intent) {
            Image(systemName: name)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 30, height: 36)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct WidgetArtworkBackground: View {
    let theme: WidgetTheme
    let artworkData: Data?

    var body: some View {
        if theme == .artwork, let data = artworkData, let image = UIImage(data: data), let average = image.averageColor {
            LinearGradient(
                colors: [Color(average).opacity(0.88), Color(average).opacity(0.48), .black.opacity(0.88)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            theme.backgroundColor
        }
    }
}

extension UIImage {
    var averageColor: UIColor? {
        guard let input = CIImage(image: self),
              let filter = CIFilter(name: "CIAreaAverage", parameters: [
                kCIInputImageKey: input,
                kCIInputExtentKey: CIVector(cgRect: input.extent)
              ]), let output = filter.outputImage else { return nil }
        var rgba = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: kCFNull as Any]).render(
            output, toBitmap: &rgba, rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8, colorSpace: nil
        )
        return UIColor(red: CGFloat(rgba[0]) / 255, green: CGFloat(rgba[1]) / 255,
                       blue: CGFloat(rgba[2]) / 255, alpha: 1)
    }
}
