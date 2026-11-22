import SwiftUI
import WidgetKit
import AppIntents

/// Control Center & Lock Screen quick toggle for Live Lyrics (iOS 18+).
@available(iOS 18.0, *)
struct CaraokeControlWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.caraoke.control.liveLyrics") {
            ControlWidgetButton(action: ResyncWidgetIntent()) {
                Label("Resync Lyrics", systemImage: "music.mic")
            }
        }
        .displayName("Resync Lyrics")
        .description("Resync Caraoke Live Lyrics for Lock Screen and CarPlay.")
    }
}
