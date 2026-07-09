// WatchTailer.swift — incremental JSONL tailing for the agent watch window.
//
// Each tick reads ONLY the bytes appended since the last read (a 23 MB session
// transcript is scanned once, then followed in O(delta)), carries a trailing
// partial line between reads, pairs tool results onto their pending tool events,
// and caps retained events so a marathon session can't grow unbounded memory.
// Pure state-in/state-out over a file path — no clocks besides the caller's `now`.

import Foundation

struct WatchTailState: Sendable, Hashable {
    var offset: UInt64 = 0            // next byte to read
    var carry: String = ""            // trailing partial line from the last read
    var events: [WatchEvent] = []
    var pending: [String: Int] = [:]  // toolKey → index into `events` awaiting a result
    var seq: Int = 0                  // monotonically increasing event-id source
    var trimmed = 0                   // events dropped from the front (cap) — surfaced in the UI
    var bootstrapped = false          // first read skipped an oversized prefix
    var lastGrowth: Date? = nil       // wall time the file last gained bytes ("streaming" pulse)
}

enum WatchTailer {
    static let maxEvents = 500
    static let bootstrapBytes: UInt64 = 768 * 1024

    /// Advance the tail: stat the file, read any appended bytes, parse the complete
    /// lines into events, attach results to pending tool calls. A file that shrank
    /// (rotation/truncation) resets and re-bootstraps from its tail.
    static func advance(path: String, state: WatchTailState, now: Date) -> WatchTailState {
        guard let fh = FileHandle(forReadingAtPath: path) else { return state }
        defer { try? fh.close() }
        let size = (try? fh.seekToEnd()) ?? 0
        var s = state
        if size < s.offset { s = WatchTailState() }            // truncated/rotated → start over
        guard size > s.offset else { return s }

        if s.offset == 0, size > bootstrapBytes {              // huge existing file: start near the end
            s.offset = size - bootstrapBytes
            s.bootstrapped = true
        }
        try? fh.seek(toOffset: s.offset)
        let data = (try? fh.readToEnd()) ?? Data()
        s.offset += UInt64(data.count)
        s.lastGrowth = now

        var text = s.carry + String(decoding: data, as: UTF8.self)
        if s.bootstrapped, s.events.isEmpty, s.carry.isEmpty {
            // The bootstrap window almost certainly opened mid-line — drop the fragment.
            if let nl = text.firstIndex(of: "\n") { text = String(text[text.index(after: nl)...]) }
        }
        let endsWithNewline = text.hasSuffix("\n")
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        s.carry = endsWithNewline ? "" : (lines.popLast() ?? "")

        for line in lines { apply(line: line, to: &s) }
        return s
    }

    static func apply(line: String, to s: inout WatchTailState) {
        for item in WatchTranscriptParser.items(line: line) {
            switch item {
            case .event(var event, let toolKey):
                s.seq += 1
                event.id = "e\(s.seq)"
                s.events.append(event)
                if let toolKey { s.pending[toolKey] = s.events.count - 1 }
            case .result(let key, let body, let isError):
                if let idx = s.pending.removeValue(forKey: key), s.events.indices.contains(idx) {
                    s.events[idx].output = body
                    s.events[idx].isError = isError
                } else {
                    // Its call was trimmed away (or predates the bootstrap window) —
                    // still show the result rather than silently dropping it.
                    s.seq += 1
                    s.events.append(WatchEvent(id: "e\(s.seq)", kind: .tool, title: "tool result",
                                               body: "", output: body, isError: isError))
                }
            }
        }
        trim(&s)
    }

    /// Enforce the retention cap, keeping pending tool-result indices valid.
    static func trim(_ s: inout WatchTailState) {
        let overflow = s.events.count - maxEvents
        guard overflow > 0 else { return }
        s.events.removeFirst(overflow)
        s.trimmed += overflow
        var rebased: [String: Int] = [:]
        for (key, idx) in s.pending where idx >= overflow { rebased[key] = idx - overflow }
        s.pending = rebased
    }
}
