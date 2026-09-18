import SwiftUI
import UIKit

/// Widget background: the song's own cover, blurred and darkened, when the
/// theme follows the artwork; otherwise the flat theme colour.
///
/// Lives in its own file because BOTH targets need it, and they share source
/// files by explicit path in `project.yml` rather than by module:
/// - the widget extension paints it behind `CaraokeWidgetEntryView`,
///   `VinylWidgetView` and the CarPlay tiles;
/// - the app paints it behind `HomeWidgetPreview`, so the Widget section's
///   preview follows the song's cover exactly like the real Home Screen widget
///   instead of advertising a hardcoded gradient (build 40's bug).
///
/// Build 54 — blurred cover instead of an average-colour wash. Up to here this
/// view painted a `LinearGradient` from the cover's single dominant colour,
/// which is why every tile read as flat: one hue, no image. The competitor's
/// widget that the user compared against uses the cover itself, blurred, and
/// the difference is the whole reason their tile looks richer. The recipe is
/// the one Apple Music's full-screen player uses — the cover scaled past the
/// edges, blurred hard, then darkened so the lyrics stay legible on top.
struct WidgetArtworkBackground: View {
    let theme: WidgetTheme
    let artworkData: Data?

    private var artwork: UIImage? {
        artworkData.flatMap(UIImage.init(data:))
    }

    var body: some View {
        if theme == .artwork, let artwork {
            GeometryReader { geo in
                ZStack {
                    Color.black
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFill()
                        // Overscan before the blur. SwiftUI's blur samples
                        // outside the image's own bounds, so an image laid out
                        // exactly to the frame would have its blurred edge pull
                        // the surrounding black back in and dim the tile instead
                        // of softening it. This is also what makes the cover
                        // read as an ambient backdrop rather than as a picture
                        // of the artwork.
                        .scaleEffect(1.4)
                        .blur(radius: 36, opaque: true)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                    LinearGradient(
                        colors: [Color.black.opacity(0.35),
                                 Color.black.opacity(0.58),
                                 Color.black.opacity(0.74)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
        } else {
            theme.backgroundColor
        }
    }
}
