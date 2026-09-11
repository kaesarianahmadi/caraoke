import SwiftUI

/// Widget background: the artwork's average colour when the theme follows the
/// cover, otherwise the flat theme colour.
///
/// Lives in its own file because BOTH targets need it, and they share source
/// files by explicit path in `project.yml` rather than by module:
/// - the widget extension paints it behind `CaraokeWidgetEntryView` and
///   `VinylWidgetView`;
/// - the app paints it behind `HomeWidgetPreview`, so the Widget section's
///   preview follows the song's colour exactly like the real Home Screen
///   widget instead of advertising a hardcoded gradient (build 40's bug).
///
/// It was previously declared inside `VinylWidgetView.swift`, which the app
/// target excludes — that is why referencing it from `HomeView` failed to
/// build.
struct WidgetArtworkBackground: View {
    let theme: WidgetTheme
    let artworkColorHex: String?

    var body: some View {
        if theme == .artwork, let hex = artworkColorHex, let color = Color(hexString: hex) {
            ZStack {
                Color.black
                LinearGradient(
                    colors: [color.opacity(0.48), color.opacity(0.22), Color(white: 0.04)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        } else {
            theme.backgroundColor
        }
    }
}
