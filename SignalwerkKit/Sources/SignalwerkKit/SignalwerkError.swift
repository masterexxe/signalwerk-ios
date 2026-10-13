import Foundation

/// Fehler mit Texten für Menschen. Fehlertexte vom Dashboard kommen unverändert durch.
public enum SignalwerkError: Error, LocalizedError, Equatable {
    /// Token ungültig oder entzogen: neu anmelden.
    case unauthorized(String)
    /// Das Dashboard hat abgelehnt (Status und Text vom Server).
    case server(status: Int, message: String)
    /// Keine Verbindung zum Dashboard.
    case network(String)
    /// Antwort nicht lesbar (etwa ältere Signalwerk-Version ohne App-Schnittstelle).
    case invalidResponse(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .unauthorized(let message): return message
        case .server(_, let message): return message
        case .network(let message): return message
        case .invalidResponse(let message): return message
        case .cancelled: return "Abgebrochen."
        }
    }

    public var isUnauthorized: Bool {
        if case .unauthorized = self { return true }
        return false
    }

    static func from(_ error: Error) -> SignalwerkError {
        if let known = error as? SignalwerkError { return known }
        if error is CancellationError { return .cancelled }
        if let url = error as? URLError { return from(url) }
        return .network(error.localizedDescription)
    }

    static func from(_ error: URLError) -> SignalwerkError {
        switch error.code {
        case .cancelled:
            return .cancelled
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return .network("Keine Internetverbindung.")
        case .timedOut:
            return .network("Das Dashboard antwortet nicht.")
        case .cannotFindHost, .dnsLookupFailed:
            return .network("Adresse nicht gefunden. Bitte die Adresse des Dashboards prüfen.")
        case .cannotConnectToHost:
            return .network("Das Dashboard ist nicht erreichbar.")
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot:
            return .network("Keine sichere Verbindung zum Dashboard möglich.")
        case .appTransportSecurityRequiresSecureConnection:
            return .network("Nur https-Adressen sind erlaubt.")
        default:
            return .network("Verbindung fehlgeschlagen (\(error.code.rawValue)).")
        }
    }
}
