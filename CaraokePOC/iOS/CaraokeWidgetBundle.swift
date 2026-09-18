import SwiftUI
import WidgetKit

/// Widget extension bundle entry point.
///
/// Three things are exposed, and all three matter to CarPlay:
/// `LyricsLiveActivity` (the Lock Screen banner, its CarPlay mirror, and the
/// Dynamic Island), the Home Screen widget, and the three small CarPlay
/// tiles the driver can place in a CarPlay widget stack.
@main
struct CaraokeWidgetBundle: WidgetBundle {
    var body: some Widget {
        LyricsLiveActivity()
        CaraokeWidget()
        CaraokePlayerWidget()
        CaraokeLyricsWidget()
        CaraokeHybridWidget()
    }
}
