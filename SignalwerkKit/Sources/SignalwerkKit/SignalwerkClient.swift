import Foundation

/// HTTP-Zugang zu /api/app/v1. Liest Fehler als { ok: false, error } und macht daraus
/// `SignalwerkError` mit dem Text des Dashboards.
public final class SignalwerkClient {
    public let baseURL: URL
    public private(set) var token: String?
    let session: URLSession

    public init(baseURL: URL, token: String? = nil, session: URLSession? = nil) {
        self.baseURL = baseURL
        self.token = token
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 20
            configuration.waitsForConnectivity = false
            configuration.httpAdditionalHeaders = ["User-Agent": "Signalwerk-iOS/1"]
            self.session = URLSession(configuration: configuration)
        }
    }

    public func setToken(_ token: String?) {
        self.token = token
    }

    public static let decoder = JSONDecoder()

    func url(_ path: String, query: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) ?? URLComponents()
        components.path = "/api/app/v1" + path
        components.queryItems = query.isEmpty ? nil : query
        return components.url ?? baseURL
    }

    func makeRequest(_ method: String, _ path: String, query: [URLQueryItem] = [], body: [String: Any]? = nil, authorized: Bool = true) throws -> URLRequest {
        var request = URLRequest(url: url(path, query: query))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authorized, let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        }
        return request
    }

    /// Anfrage schicken und die Antwort als `T` lesen.
    public func send<T: Decodable>(_ type: T.Type, _ method: String, _ path: String, query: [URLQueryItem] = [], body: [String: Any]? = nil, authorized: Bool = true) async throws -> T {
        let request = try makeRequest(method, path, query: query, body: body, authorized: authorized)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SignalwerkError.from(error)
        }
        return try SignalwerkClient.decodeResponse(type, data: data, response: response)
    }

    /// Aktion schicken: { ok, data, warning } oder Fehler.
    public func action<T: Decodable>(_ type: T.Type, _ path: String, body: [String: Any]? = nil, method: String = "POST") async throws -> (data: T?, warning: String?) {
        let reply = try await send(ActionReply<T>.self, method, path, body: body)
        if !reply.ok {
            throw SignalwerkError.server(status: 400, message: reply.error ?? "Aktion fehlgeschlagen.")
        }
        return (reply.data, reply.warning)
    }

    static func decodeResponse<T: Decodable>(_ type: T.Type, data: Data, response: URLResponse) throws -> T {
        guard let http = response as? HTTPURLResponse else {
            throw SignalwerkError.invalidResponse("Keine Antwort vom Dashboard.")
        }
        if (200..<300).contains(http.statusCode) {
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw SignalwerkError.invalidResponse("Antwort des Dashboards nicht lesbar. Läuft dort Signalwerk 2.5 oder neuer?")
            }
        }
        let message = errorMessage(data) ?? defaultMessage(status: http.statusCode)
        if http.statusCode == 401 { throw SignalwerkError.unauthorized(message) }
        throw SignalwerkError.server(status: http.statusCode, message: message)
    }

    static func errorMessage(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = object["error"] as? String, !error.isEmpty { return error }
        return nil
    }

    static func defaultMessage(status: Int) -> String {
        switch status {
        case 401: return "Nicht angemeldet."
        case 403: return "Keine Berechtigung."
        case 404: return "Das Dashboard kennt die App-Schnittstelle nicht. Bitte Signalwerk auf 2.5 oder neuer aktualisieren."
        case 429: return "Zu viele Anfragen. Bitte kurz warten."
        case 500...599: return "Fehler im Dashboard (\(status))."
        default: return "Anfrage abgelehnt (\(status))."
        }
    }
}
