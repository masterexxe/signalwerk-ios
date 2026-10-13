import SwiftUI
import SignalwerkKit

@main
struct SignalwerkApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(Palette.amber)
                .onAppear { model.start() }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active: model.sceneBecameActive()
                    case .background: model.sceneEnteredBackground()
                    default: break
                    }
                }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            switch model.phase {
            case .starting:
                ProgressView()
                    .tint(Palette.amber)
            case .signedOut:
                LoginView()
            case .signedIn:
                if let session = model.session {
                    MainView()
                        .environment(session)
                        .id(ObjectIdentifier(session))
                }
            }
            ToastOverlay(center: model.toasts)
        }
    }
}
