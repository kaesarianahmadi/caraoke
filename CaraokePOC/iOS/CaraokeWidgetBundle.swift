import SwiftUI
import WidgetKit

/// Widget extension bundle entry point: the Live Activity is the only widget
/// in the PoC (no Home Screen widgets — out of scope for the MVP).
@main
struct CaraokeWidgetBundle: WidgetBundle {
    var body: some Widget {
        LyricsLiveActivity()
    }
}
