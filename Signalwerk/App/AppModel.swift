import Foundation
import Observation
import SignalwerkKit
import UIKit

/// Wurzel der App: angemeldet oder nicht, Start, Abmelden, Demo.
@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case starting
        case signedOut
        case signedIn
    }

    private(set) var phase: Phase = .starting
    private(set) var session: AppSession?
    let toasts = ToastCenter()
    /// Grund der letzten Abmeldung (zeigt die Anmeldeseite).
    var signOutMessage: String?
    var lastServer: String = UserDefaults.standard.string(forKey: "signalwerk.server") ?? ServerAddress.suggested

    static var isUITesting: Bool { ProcessInfo.processInfo.arguments.contains("-uiTesting") }

    func start() {
        guard phase == .starting else { return }
        PushCenter.shared.model = self
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-demo") {
            startDemo(live: false)
            return
        }
        if let stored = TokenStore.load(), let server = URL(string: stored.server) {
            open(LiveBackend(server: server, token: stored.token), me: stored.me, server: server)
        } else {
            phase = .signedOut
        }
    }

    /// Nach erfolgreicher Anmeldung (Passwort oder Webseite).
    func signedIn(server: URL, payload: SessionPayload) {
        let me = MeResponse(user: payload.user, permissions: payload.permissions, device: payload.device, server: payload.server)
        TokenStore.save(StoredSession(server: server.absoluteString, token: payload.token, me: me))
        lastServer = ServerAddress.display(server)
        UserDefaults.standard.set(lastServer, forKey: "signalwerk.server")
        signOutMessage = nil
        open(LiveBackend(server: server, token: payload.token), me: me, server: server)
        toasts.show("Angemeldet als \(me.user.displayName).")
    }

    func startDemo(live: Bool = true) {
        let demo = DemoBackend(simulateLive: live)
        let device = DeviceInfo(id: "demoipad000000000001", name: UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone", platform: AppModel.platform, createdAt: SignalwerkDate.string(Date()), lastSeenAt: SignalwerkDate.string(Date()), push: nil, own: true)
        let me = MeResponse(user: DemoBackend.user, permissions: DemoBackend.permissions, device: device, server: DemoBackend.server)
        signOutMessage = nil
        open(demo, me: me, server: nil)
    }

    private func open(_ backend: SignalwerkBackend, me: MeResponse, server: URL?) {
        session?.end()
        let session = AppSession(backend: backend, me: me, toasts: toasts)
        session.context.onUnauthorized = { [weak self] message in
            self?.signOut(message: message, revokeRemotely: false)
        }
        if let server, let backend = backend as? LiveBackend {
            session.onMeUpdated = { me in
                guard let token = backend.client.token else { return }
                TokenStore.save(StoredSession(server: server.absoluteString, token: token, me: me))
            }
        }
        self.session = session
        phase = .signedIn
        session.activate()
        if !session.isDemo && !AppModel.isUITesting {
            // War Push schon erlaubt: Token neu holen und beim Dashboard hinterlegen.
            Task { await PushCenter.shared.refresh() }
        }
    }

    func signOut(message: String? = nil, revokeRemotely: Bool = true) {
        guard let session else {
            phase = .signedOut
            return
        }
        session.end()
        if !session.isDemo {
            if revokeRemotely {
                let backend = session.backend
                Task { try? await backend.logout() }
            }
            TokenStore.clear()
        }
        self.session = nil
        signOutMessage = message
        phase = .signedOut
    }

    func sceneBecameActive() {
        session?.activate()
    }

    func sceneEnteredBackground() {
        session?.deactivate()
    }

    static var platform: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "ipados" : "ios"
    }

    /// Name des Geräts für die Geräteliste im Dashboard.
    static var deviceName: String {
        let idiom = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        let name = UIDevice.current.name
        // Seit iOS 16 liefert name ohne Sonderrecht nur "iPhone"/"iPad"; dann das Modell dazu.
        if name == "iPhone" || name == "iPad" {
            return "\(idiom) · \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        }
        return name
    }
}
