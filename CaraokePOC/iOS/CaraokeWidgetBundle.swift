import SwiftUI
import WidgetKit

/// Widget extension bundle entry point: Live Activity + Standard persistent widget
@main
struct CaraokeWidgetBundle: WidgetBundle {
    var body: some Widget {
        LyricsLiveActivity()
        CaraokeWidget()
    }
}
