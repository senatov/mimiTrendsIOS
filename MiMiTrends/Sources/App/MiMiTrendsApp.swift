import SwiftUI

@main
struct MiMiTrendsApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var radarSession = RadarSession()

    init() {
        #if os(macOS)
        LocalAccountInstanceGuard.activateExistingInstanceOrExit()
        #endif
        let log = AppDiagnostics.shared
        log.record(.info, "App", "launched", "version=\(AppIdentity.version) pid=\(ProcessInfo.processInfo.processIdentifier)")
        if let url = log.fileURL() {
            log.record(.info, "App", "diagnostics-ready", "file=\(url.path)")
        }
    }
    
    /// App version from CFBundleShortVersionString (e.g. "0.9.4")
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
    }

    var body: some Scene {
        WindowGroup(AppIdentity.windowTitle) {
            ContentView()
                .environment(radarSession)
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 780)
        #endif
        .onChange(of: scenePhase) { _, phase in
            AppDiagnostics.shared.record(.info, "App", "scene-phase", "phase=\(phase)")
            if phase != .active {
                radarSession.stop()
            }
        }
    }
}
