import SwiftUI
import ServiceManagement
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        appLogger.info("applicationDidFinishLaunching")
        logToFile("applicationDidFinishLaunching — pid=\(ProcessInfo.processInfo.processIdentifier)")
        try? SMAppService.mainApp.register()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appLogger.warning("applicationWillTerminate")
        logToFile("applicationWillTerminate")
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        appLogger.warning("applicationShouldTerminate called")
        logToFile("applicationShouldTerminate called")
        return .terminateNow
    }
}

@main
struct StockMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            DropdownView()
                .environmentObject(appState)
        } label: {
            MenuBarLabel()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)
    }
}
