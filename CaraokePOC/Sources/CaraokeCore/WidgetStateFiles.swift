import CryptoKit
import Darwin
import Foundation

/// Shared widget files. A file lock coordinates app and extension processes;
/// actor isolation alone cannot make their read/compare/write atomic.
struct WidgetStateFiles: Sendable {
    let directory: URL

    private struct State: Codable {
        var payload: SharedWidgetPayload
        let cover: String?
        let nextCover: String?
    }

    func read() throws -> SharedWidgetPayload? {
        try withLock { try readState() }
    }

    func write(_ payload: SharedWidgetPayload?) throws {
        try withLock { try writeState(payload) }
    }

    /// A repair must not overwrite playback published while its request ran.
    func replace(_ expected: SharedWidgetPayload, with payload: SharedWidgetPayload) throws -> SharedWidgetPayload? {
        try withLock {
            let current = try readState()
            guard current == expected else { return current }
            if current != payload { try writeState(payload) }
            return payload
        }
    }

    func readSettings() throws -> SharedWidgetSettings {
        try decode(SharedWidgetSettings.self, at: directory.appendingPathComponent("settings.json")) ?? .init()
    }

    func writeSettings(_ settings: SharedWidgetSettings) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encode(settings, at: directory.appendingPathComponent("settings.json"))
    }

    private var stateURL: URL { directory.appendingPathComponent("state.json") }
    private var covers: URL { directory.appendingPathComponent("covers", isDirectory: true) }

    private func readState() throws -> SharedWidgetPayload? {
        guard var state = try decode(State.self, at: stateURL) else { return nil }
        state.payload.artworkData = try state.cover.map(readCover)
        state.payload.nextArtworkData = try state.nextCover.map(readCover)
        return state.payload
    }

    private func writeState(_ payload: SharedWidgetPayload?) throws {
        let keep: Set<String>
        if var payload {
            try FileManager.default.createDirectory(at: covers, withIntermediateDirectories: true)
            let cover = try payload.artworkData.map(writeCover)
            let next = try payload.nextArtworkData.map(writeCover)
            payload.artworkData = nil
            payload.nextArtworkData = nil
            try encode(State(payload: payload, cover: cover, nextCover: next), at: stateURL)
            keep = Set([cover, next].compactMap { $0 })
        } else {
            do { try FileManager.default.removeItem(at: stateURL) }
            catch CocoaError.fileNoSuchFile { }
            keep = []
        }
        // Cleanup failure must not invalidate a successful atomic publication.
        for url in (try? FileManager.default.contentsOfDirectory(at: covers, includingPropertiesForKeys: nil)) ?? []
            where url.pathExtension == "jpg" && !keep.contains(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func readCover(_ name: String) throws -> Data {
        guard name.count == 68, name.hasSuffix(".jpg"),
              name.dropLast(4).utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return try Data(contentsOf: covers.appendingPathComponent(name))
    }

    private func writeCover(_ data: Data) throws -> String {
        let name = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() + ".jpg"
        let url = covers.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) { try data.write(to: url, options: .atomic) }
        return name
    }

    private func decode<T: Decodable>(_ type: T.Type, at url: URL) throws -> T? {
        do { return try JSONDecoder().decode(type, from: Data(contentsOf: url)) }
        catch CocoaError.fileReadNoSuchFile { return nil }
    }

    private func encode<T: Encodable>(_ value: T, at url: URL) throws {
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }

    private func withLock<T>(_ operation: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let descriptor = open(directory.appendingPathComponent("state.lock").path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        while flock(descriptor, LOCK_EX) != 0 {
            guard errno == EINTR else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
        return try operation()
    }
}
