import SwiftUI

/// Shared lyric layout used by every surface: the Lock Screen Live Activity,
/// the Dynamic Island expanded region, and the CarPlay small-family tile.
/// One view, three contexts — this is the whole point of the design.
struct LyricTileView: View {
    let title: String
    let artist: String
    let currentLine: String
    let nextLine: String?
    let isPlaying: Bool
    let progress: Double
    /// CarPlay small layout is more compact than the Lock Screen banner.
    let isCarPlaySmall: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: isCarPlaySmall ? 2 : 4) {
            if !isCarPlaySmall {
                HStack(spacing: 6) {
                    Image(systemName: "music.note")
                        .font(.caption)
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    if !isPlaying {
                        Image(systemName: "pause.circle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
            }

            Text(currentLine)
                .font(isCarPlaySmall ? .headline : .title3.weight(.semibold))
                .lineLimit(isCarPlaySmall ? 2 : 3)
                .minimumScaleFactor(0.7)

            if let nextLine, !nextLine.isEmpty {
                Text(nextLine)
                    .font(isCarPlaySmall ? .caption : .subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(isCarPlaySmall ? 1 : 2)
                    .minimumScaleFactor(0.7)
            }

            if !isCarPlaySmall {
                ProgressView(value: progress)
                    .tint(.accentColor)
            }
        }
        .padding(isCarPlaySmall ? 8 : 12)
    }
}
