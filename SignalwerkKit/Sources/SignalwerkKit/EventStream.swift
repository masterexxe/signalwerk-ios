import Foundation

/// Server-Sent Events lesen. Jede "data:"-Zeile ergibt ein Ereignis mit dem zuletzt genannten
/// Namen; Leerzeilen braucht der Leser nicht (das Dashboard schickt je Ereignis eine Datenzeile).
public struct SSEParser {
    private var name = "message"

    public init() {}

    /// Eine Zeile verarbeiten; liefert ein Ereignis, wenn die Zeile eins abschließt.
    public mutating func feed(_ rawLine: String) -> ServerEvent? {
        let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
        if line.isEmpty {
            name = "message"
            return nil
        }
        if line.hasPrefix(":") { return nil }
        if line.hasPrefix("event:") {
            name = line.dropFirst("event:".count).trimmingCharacters(in: .whitespaces)
            return nil
        }
        if line.hasPrefix("data:") {
            let data = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
            let event = ServerEvent(name: name, data: data)
            name = "message"
            return event
        }
        return nil
    }
}

enum EventStream {
    static func open(request: URLRequest?, session: URLSession) -> AsyncThrowingStream<ServerEvent, Error> {
        AsyncThrowingStream { continuation in
            guard var request else {
                continuation.finish(throwing: SignalwerkError.invalidResponse("Ungültige Adresse."))
                return
            }
            request.timeoutInterval = 3600
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            let task = Task { [request] in
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw SignalwerkError.invalidResponse("Keine Antwort vom Dashboard.")
                    }
                    guard http.statusCode == 200 else {
                        if http.statusCode == 401 { throw SignalwerkError.unauthorized("Die Anmeldung gilt nicht mehr. Bitte in der App neu anmelden.") }
                        throw SignalwerkError.server(status: http.statusCode, message: SignalwerkClient.defaultMessage(status: http.statusCode))
                    }
                    var parser = SSEParser()
                    for try await line in bytes.lines {
                        if let event = parser.feed(line) {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: SignalwerkError.from(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
