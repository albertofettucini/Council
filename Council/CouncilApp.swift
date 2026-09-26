//
//  CouncilApp.swift
//  Council
//
//  Created by Joseph on 28.05.2026.
//

import AppKit
import CouncilKit
import SwiftUI
import Sparkle
import UserNotifications

/// One shared Sparkle updater for the app — started at launch so the background
/// schedule runs; Settings exposes the manual check + the auto toggle.
@MainActor
enum Updater {
    static let controller = SPUStandardUpdaterController(startingUpdater: true,
                                                         updaterDelegate: nil,
                                                         userDriverDelegate: nil)
}

extension Notification.Name {
    /// Posted (object = session UUID) when the user clicks an outcome-reminder notification.
    static let councilOpenSession = Notification.Name("council.openSession")
}

/// The last clicked reminder, kept outside any view: a click can arrive with the window closed
/// (⌘W, app still in the Dock) or before the first ContentView exists on a cold launch.
@MainActor enum ReminderClick {
    static var pendingSessionID: UUID?
}

/// Notification plumbing the SwiftUI App can't do on its own: register the reminder category and
/// receive clicks. Without a delegate a reminder that fires while Council is frontmost is swallowed
/// silently, and a click on one would only bring the app forward.
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let log = UNNotificationAction(identifier: CouncilStore.reminderLogActionID,
                                       title: "Log outcome", options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: CouncilStore.reminderCategoryID,
                                   actions: [log], intentIdentifiers: [], options: [])
        ])
    }

    /// Show the banner even when Council is the active app — the reminder is the point.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// Click (or "Log outcome") → open the Journal on that decision.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let raw = info[CouncilStore.reminderSessionKey] as? String, let id = UUID(uuidString: raw) else { return }
        await MainActor.run {
            ReminderClick.pendingSessionID = id
            NSApp.activate(ignoringOtherApps: true)
            for w in NSApp.windows where w.isMiniaturized { w.deminiaturize(nil) }
            if NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) {
                NotificationCenter.default.post(name: .councilOpenSession, object: id)
            } else {
                // No window (closed with ⌘W): go through the standard reopen path, which makes the
                // WindowGroup create one; its ContentView then picks up the pending id on appear.
                NSWorkspace.shared.open(Bundle.main.bundleURL)
            }
        }
    }
}

@main
struct CouncilApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = CouncilStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                // Session writes are coalesced (see CouncilStore.scheduleSessionWrite); quitting
                // must not drop one that is still queued.
                .onReceive(NotificationCenter.default.publisher(
                    for: NSApplication.willTerminateNotification)) { _ in
                    store.flushPendingWrite()
                }
                // Coming back from System Settings (notifications switched on/off) or from an update:
                // re-read the grant and re-sync the pending reminders. Idempotent and cheap.
                .onReceive(NotificationCenter.default.publisher(
                    for: NSApplication.didBecomeActiveNotification)) { _ in
                    store.syncReminderNotifications()
                }
        }
        .windowStyle(.hiddenTitleBar)   // immersive, brutalist — content goes edge to edge
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1300, height: 820)
    }
}
