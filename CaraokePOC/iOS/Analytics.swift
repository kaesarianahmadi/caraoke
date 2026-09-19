import Foundation
#if canImport(TelemetryDeck)
import TelemetryDeck
#endif

/// Lightweight privacy-first analytics wrapper over TelemetryDeck.
enum Analytics {
    static func initialize() {
        guard let appID = SecretsLoader.telemetryAppID else { return }
        #if canImport(TelemetryDeck)
        let config = TelemetryDeck.Config(appID: appID)
        TelemetryDeck.initialize(config: config)
        #endif
    }

    static func signal(_ name: String, parameters: [String: String] = [:]) {
        #if canImport(TelemetryDeck)
        TelemetryDeck.signal(name, parameters: parameters)
        #endif
    }
}
