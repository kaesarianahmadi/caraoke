import Foundation
import Yams

/// Converts real provider word timestamps into short display phrases.
/// Invalid or ambiguous word timing falls back to the original line timing.
enum LyricsFileParser {
    private struct Document: Decodable {
        let version: String
        let metadata: Metadata
        let lines: [Line]?
    }
    private struct Metadata: Decodable {
        let offset_ms: Int?
        let instrumental: Bool?
    }
    private struct Line: Decodable {
        let text: String
        let start_ms: Int
        let end_ms: Int?
        let words: [Word]?
    }
    private struct Word: Decodable {
        let text: String
        let start_ms: Int
        let end_ms: Int?
    }

    static func parse(_ yaml: String, maxWords: Int = 4) -> LyricTrack? {
        guard yaml.utf8.count <= 1_000_000,
              let node = try? Yams.compose(yaml: yaml),
              validNode(node, depth: 0),
              let document = try? YAMLDecoder().decode(Document.self, from: node),
              document.version == "1.0", document.metadata.offset_ms == nil,
              document.metadata.instrumental != true, let lines = document.lines,
              !lines.isEmpty, lines.count <= 2000 else { return nil }
        var fullLines: [LyricLine] = []
        var result: [LyricLine] = []
        var usedWordTiming = false
        for (index, line) in lines.enumerated() {
            let next = index + 1 < lines.count ? lines[index + 1].start_ms : nil
            guard line.start_ms >= 0, next.map({ $0 > line.start_ms }) ?? true,
                  line.end_ms.map({ end in end >= line.start_ms && (next.map { end <= $0 } ?? true) }) ?? true else { return nil }
            fullLines.append(LyricLine(startMs: line.start_ms, text: line.text))
            let words = line.words ?? []
            let valid = !words.isEmpty && words.count <= 500 &&
                words.map(\.text).joined() == line.text &&
                words[0].start_ms == line.start_ms &&
                zip(words, words.dropFirst()).allSatisfy { $0.start_ms < $1.start_ms } &&
                words.allSatisfy { word in
                    let parts = word.text.split(whereSeparator: { $0.isWhitespace })
                    return parts.count <= 1 && word.start_ms >= line.start_ms &&
                        (line.end_ms.map { word.start_ms <= $0 } ?? true) &&
                        (next.map { word.start_ms < $0 } ?? true) &&
                        (word.end_ms.map { $0 >= word.start_ms } ?? true)
                }
            guard valid else {
                result.append(LyricLine(startMs: line.start_ms, text: line.text))
                continue
            }
            usedWordTiming = true
            let limit = max(1, maxWords)
            var chunk = ""
            var chunkStart = line.start_ms
            var count = 0
            for word in words {
                let startsWord = chunk.isEmpty || chunk.last?.isWhitespace == true
                if startsWord && count == limit {
                    result.append(LyricLine(startMs: chunkStart, text: chunk.trimmingCharacters(in: .whitespacesAndNewlines)))
                    chunk = ""
                    chunkStart = word.start_ms
                    count = 0
                }
                if chunk.isEmpty { chunkStart = word.start_ms }
                if startsWord { count += 1 }
                chunk += word.text
            }
            if !chunk.isEmpty {
                result.append(LyricLine(startMs: chunkStart, text: chunk.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }
        guard !fullLines.isEmpty, !result.isEmpty,
              zip(result, result.dropFirst()).allSatisfy({ $0.startMs < $1.startMs }) else { return nil }
        return LyricTrack(lines: fullLines, compactPhrases: result, hasWordTiming: usedWordTiming)
    }

    private static func validNode(_ node: Node, depth: Int) -> Bool {
        guard depth <= 12, node.anchor == nil else { return false }
        switch node {
        case .alias: return false
        case .scalar(let value):
            return [Tag.Name.implicit.rawValue, Tag.Name.str.rawValue, Tag.Name.int.rawValue,
                    Tag.Name.bool.rawValue, Tag.Name.null.rawValue].contains(value.tag.rawValue)
        case .sequence(let values):
            return [Tag.Name.implicit.rawValue, Tag.Name.seq.rawValue].contains(values.tag.rawValue) &&
                values.count <= 5000 && values.allSatisfy { validNode($0, depth: depth + 1) }
        case .mapping(let pairs):
            guard [Tag.Name.implicit.rawValue, Tag.Name.map.rawValue].contains(pairs.tag.rawValue) else { return false }
            var keys = Set<String>()
            for pair in pairs {
                guard let key = pair.key.string, keys.insert(key).inserted,
                      validNode(pair.value, depth: depth + 1) else { return false }
            }
            return true
        }
    }
}
