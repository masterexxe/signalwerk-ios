import Foundation
import Observation
import SignalwerkKit

/// Zahlen von heute, laufender Stream und Technik.
@MainActor
@Observable
final class OverviewStore {
    private(set) var overview: Overview?
    private(set) var loading = false
    private let context: SessionContext

    init(context: SessionContext) {
        self.context = context
    }

    func load() async {
        loading = true
        defer { loading = false }
        do {
            overview = try await context.backend.overview()
        } catch {
            // Die Übersicht läuft im Hintergrund mit; Netzfehler nicht jedes Mal melden.
            if let known = error as? SignalwerkError, known.isUnauthorized {
                context.report(error)
            } else if overview == nil {
                context.report(error)
            }
        }
    }
}

/// Statistik eines Kanals (laufender oder letzter Stream).
@MainActor
@Observable
final class StatsStore {
    private(set) var snapshot: StreamSnapshot?
    private(set) var login: String?
    private(set) var channels: [Channel] = []
    private(set) var loading = false
    private(set) var message: String?
    private let context: SessionContext

    init(context: SessionContext) {
        self.context = context
    }

    func load() async {
        loading = true
        defer { loading = false }
        do {
            if channels.isEmpty {
                let response = try await context.backend.channels()
                channels = response.channels
                if login == nil, !response.defaultLogin.isEmpty { login = response.defaultLogin }
            }
            snapshot = try await context.backend.stream(login: login)
            message = nil
        } catch {
            if case .server(404, let text)? = error as? SignalwerkError {
                message = text
                snapshot = nil
            } else {
                context.report(error)
            }
        }
    }

    func select(_ login: String) {
        self.login = login
        snapshot = nil
        Task { await load() }
    }
}

/// Angemeldete Geräte (Einstellungen).
@MainActor
@Observable
final class DevicesStore {
    private(set) var devices: [DeviceInfo] = []
    private(set) var current: String?
    private(set) var loading = false
    private let context: SessionContext

    init(context: SessionContext) {
        self.context = context
    }

    func load() async {
        loading = true
        defer { loading = false }
        do {
            let response = try await context.backend.devices()
            devices = response.devices
            current = response.current
        } catch {
            context.report(error)
        }
    }

    func revoke(_ device: DeviceInfo) async {
        do {
            try await context.backend.revokeDevice(id: device.id)
            devices.removeAll { $0.id == device.id }
            context.toasts.show("\(device.name) abgemeldet.")
        } catch {
            context.report(error)
        }
    }
}
