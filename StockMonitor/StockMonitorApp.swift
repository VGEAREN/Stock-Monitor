import SwiftUI
import ServiceManagement
import AppKit
import os

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        appLogger.info("applicationDidFinishLaunching")
        logToFile("applicationDidFinishLaunching — pid=\(ProcessInfo.processInfo.processIdentifier)")
        let status = SMAppService.mainApp.status
        logToFile("SMAppService.mainApp.status = \(status.rawValue)")
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
struct StockbarApp: App {
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
