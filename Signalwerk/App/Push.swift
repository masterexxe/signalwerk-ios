import Observation
import SignalwerkKit
import UIKit
import UserNotifications

/// Mitteilungen: neue Spende oder Sub-Bomb mit „Annehmen“ und „Blockieren“ direkt in der
/// Mitteilung. Das Dashboard schickt sie über Apple (APNs), sobald dort Push eingerichtet ist.
@MainActor
@Observable
final class PushCenter {
    static let shared = PushCenter()

    static let queueCategory = "SIGNALWERK_QUEUE"
    static let acceptAction = "ACCEPT"
    static let blockAction = "BLOCK"

    enum Status: Equatable {
        case unknown
        case off
        case denied
        case waiting
        case on
        case failed(String)
    }

    private(set) var status: Status = .unknown
    private(set) var token: String?
    /// Neue Spenden und Sub-Bombs melden (gespeichert pro Gerät).
    private(set) var queueEnabled: Bool = UserDefaults.standard.object(forKey: "signalwerk.push.queue") as? Bool ?? true

    @ObservationIgnored weak var model: AppModel?
    /// Zuletzt per Mitteilung geöffnete Spende (die App springt zu den Spenden).
    var openedItem: String?

    static var environment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    func registerCategories() {
        let accept = UNNotificationAction(identifier: PushCenter.acceptAction, title: "Annehmen", options: [.authenticationRequired])
        let block = UNNotificationAction(identifier: PushCenter.blockAction, title: "Blockieren", options: [.authenticationRequired, .destructive])
        let queue = UNNotificationCategory(identifier: PushCenter.queueCategory, actions: [accept, block], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([queue])
    }

    /// Beim Start und nach der Anmeldung: Stand der Erlaubnis lesen, bei Erlaubnis registrieren.
    func refresh() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            if status != .on { status = .waiting }
            UIApplication.shared.registerForRemoteNotifications()
        case .denied:
            status = .denied
        default:
            status = .off
        }
    }

    /// Erlaubnis fragen und registrieren.
    func enable() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                status = .waiting
                setQueueEnabled(true)
                UIApplication.shared.registerForRemoteNotifications()
            } else {
                status = .denied
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func setQueueEnabled(_ enabled: Bool) {
        queueEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "signalwerk.push.queue")
        Task { await upload() }
    }

    func didRegister(_ data: Data) {
        token = data.map { String(format: "%02x", $0) }.joined()
        status = .on
        Task { await upload() }
    }

    func didFail(_ error: Error) {
        status = .failed(error.localizedDescription)
    }

    /// Token und Wunsch beim Dashboard hinterlegen.
    func upload() async {
        guard let token, let session = model?.session, !session.isDemo else { return }
        do {
            try await session.backend.registerPush(token: token, environment: PushCenter.environment, queue: queueEnabled)
        } catch {
            session.context.report(error)
        }
    }

    /// Taste in einer Mitteilung: im Hintergrund annehmen oder blockieren.
    func handle(action: String, userInfo: [AnyHashable: Any]) async {
        guard let kind = userInfo["kind"] as? String, let id = userInfo["id"] as? String else { return }
        if action == UNNotificationDefaultActionIdentifier {
            openedItem = "\(kind):\(id)"
            return
        }
        let decision: QueueAction
        switch action {
        case PushCenter.acceptAction: decision = .accept
        case PushCenter.blockAction: decision = .block
        default: return
        }
        // Die Anmeldung kommt aus dem Schlüsselbund; die Oberfläche läuft dabei evtl. nicht.
        guard let stored = TokenStore.load(), let server = URL(string: stored.server) else { return }
        if let origin = userInfo["server"] as? String, !origin.isEmpty, let originURL = URL(string: origin), originURL.host != server.host {
            return
        }
        let backend = LiveBackend(server: server, token: stored.token)
        let item = QueueItem(kind: kind, id: id, name: "", message: "", amount: "", voice: "", state: "pending", at: "")
        do {
            _ = try await backend.decide(item, action: decision)
            await model?.session?.queue.load()
        } catch {
            await notifyFailure(decision: decision, error: error)
        }
    }

    private func notifyFailure(decision: QueueAction, error: Error) async {
        let content = UNMutableNotificationContent()
        content.title = decision == .accept ? "Annehmen fehlgeschlagen" : "Blockieren fehlgeschlagen"
        content.body = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}

/// Verbindet UIKit (Push-Token, Mitteilungen) mit der SwiftUI-App.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        MainActor.assumeIsolated {
            PushCenter.shared.registerCategories()
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        MainActor.assumeIsolated {
            PushCenter.shared.didRegister(deviceToken)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        MainActor.assumeIsolated {
            PushCenter.shared.didFail(error)
        }
    }

    // Mitteilung kommt, während die App vorne ist: trotzdem zeigen (Banner, Ton).
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo
        await PushCenter.shared.handle(action: action, userInfo: userInfo)
    }
}
