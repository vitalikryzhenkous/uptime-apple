import Foundation

/// One server-sent event.
public struct SSEEvent: Equatable, Sendable {
    public var event: String
    public var id: String?
    public var data: String
}

/// Server-sent events parser fed byte by byte.
/// Not built on `AsyncBytes.lines`: that sequence drops empty lines, and an empty line is what ends an event.
public struct SSEParser: Sendable {
    private var line: [UInt8] = []
    private var lastWasCR = false
    private var event = ""
    private var id: String?
    private var data: [String] = []

    public init() {}

    /// Feed one byte; returns an event when an empty line completes it.
    public mutating func push(_ byte: UInt8) -> SSEEvent? {
        switch byte {
        case 0x0A: // \n (after \r it was already handled)
            if lastWasCR { lastWasCR = false; return nil }
            return endLine()
        case 0x0D: // \r or \r\n
            lastWasCR = true
            return endLine()
        default:
            lastWasCR = false
            line.append(byte)
            return nil
        }
    }

    private mutating func endLine() -> SSEEvent? {
        let text = String(decoding: line, as: UTF8.self)
        line.removeAll(keepingCapacity: true)
        if text.isEmpty { return dispatch() }
        if text.hasPrefix(":") { return nil } // comment

        let field: Substring, value: Substring
        if let colon = text.firstIndex(of: ":") {
            field = text[..<colon]
            var v = text[text.index(after: colon)...]
            if v.first == " " { v = v.dropFirst() }
            value = v
        } else {
            field = Substring(text)
            value = ""
        }
        switch field {
        case "event": event = String(value)
        case "data": data.append(String(value))
        case "id": id = String(value)
        default: break // `retry` and unknown fields are ignored
        }
        return nil
    }

    private mutating func dispatch() -> SSEEvent? {
        defer { event = ""; data = [] } // `id` persists across events, as in the spec
        if data.isEmpty { return nil }
        return SSEEvent(event: event.isEmpty ? "message" : event, id: id, data: data.joined(separator: "\n"))
    }
}
