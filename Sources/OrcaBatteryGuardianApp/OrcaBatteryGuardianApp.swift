import AppKit
import OrcaBatteryGuardian
import SwiftUI

@main
struct OrcaBatteryGuardianApp: App {
    @NSApplicationDelegateAdaptor(GuardianAppDelegate.self) private var appDelegate
    @StateObject private var engine = GuardianEngine()
    @Environment(\.openWindow) private var openWindow

    init() {
        BundledFontRegistrar.registerSarabun()
    }

    var body: some Scene {
        Window("Orca Battery Guardian", id: "main") {
            ContentView(engine: engine)
                .onAppear {
                    NSApp.setActivationPolicy(.accessory)
                    appDelegate.engine = engine
                    Task { @MainActor in
                        await Task.yield()
                        engine.start()
                    }
                }
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarContentView(
                engine: engine,
                onOpen: {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                },
                onRefresh: { engine.refresh() },
                onQuit: { NSApp.terminate(nil) }
            )
        } label: {
            MenuBarLabelView(percentage: engine.snapshot.percentage)
                .onAppear {
                    appDelegate.engine = engine
                    Task { @MainActor in
                        await Task.yield()
                        engine.start()
                    }
                }
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class GuardianAppDelegate: NSObject, NSApplicationDelegate {
    weak var engine: GuardianEngine?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let engine else { return .terminateNow }
        Task {
            await engine.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
