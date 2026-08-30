import Foundation

/// Loads the bundled demo fixture. Under SwiftPM this uses the generated
/// `Bundle.module`; in the standalone (CommandLineTools) build it reads the
/// file from the package layout relative to the working directory.
enum FixtureLoader {
    static func loadDemoTrack() -> LyricTrack {
        let url: URL
        #if SWIFT_PACKAGE
        url = Bundle.module.url(forResource: "demo_lyrics", withExtension: "tsv")!
        #else
        url = URL(fileURLWithPath: "Sources/CaraokeCore/Resources/demo_lyrics.tsv")
        #endif
        let raw = try! String(contentsOf: url, encoding: .utf8)
        return LyricTrack(lines: TimedLyricParser.parse(raw))
    }
}
