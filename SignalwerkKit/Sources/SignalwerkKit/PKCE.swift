import CryptoKit
import Foundation

/// Prüfwert für die Anmeldung über die Webseite (PKCE, S256).
public struct PKCE: Equatable {
    public let verifier: String
    public let challenge: String

    public init() {
        self.init(verifier: PKCE.randomString(bytes: 48))
    }

    public init(verifier: String) {
        self.verifier = verifier
        self.challenge = PKCE.challenge(for: verifier)
    }

    public static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URL(Data(digest))
    }

    /// Zufälliger Text aus base64url-Zeichen.
    public static func randomString(bytes count: Int) -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<count).map { _ in UInt8.random(in: 0...255, using: &generator) }
        return base64URL(Data(bytes))
    }

    public static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Anmeldung über die Webseite: Adresse zum Öffnen und Auswertung des Rücksprungs.
public struct WebConnect: Equatable {
    public static let callbackScheme = "signalwerk"

    public let pkce: PKCE
    public let state: String
    public let url: URL

    public init?(server: URL, deviceName: String, platform: String, pkce: PKCE = PKCE(), state: String = PKCE.randomString(bytes: 24)) {
        guard var components = URLComponents(url: server, resolvingAgainstBaseURL: false) else { return nil }
        components.path = "/app-verbinden"
        components.queryItems = [
            URLQueryItem(name: "challenge", value: pkce.challenge),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "device", value: deviceName),
            URLQueryItem(name: "platform", value: platform),
        ]
        guard let url = components.url else { return nil }
        self.pkce = pkce
        self.state = state
        self.url = url
    }

    public enum Callback: Equatable {
        case code(String)
        case cancelled
        case invalid
    }

    /// signalwerk://verbunden?code=…&state=… auswerten. Ein fremder state gilt als ungültig.
    public func evaluate(_ callback: URL) -> Callback {
        guard callback.scheme == WebConnect.callbackScheme,
              let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems
        else { return .invalid }
        let value = { (name: String) in items.first(where: { $0.name == name })?.value }
        guard value("state") == state else { return .invalid }
        if value("error") != nil { return .cancelled }
        guard let code = value("code"), !code.isEmpty else { return .invalid }
        return .code(code)
    }
}
