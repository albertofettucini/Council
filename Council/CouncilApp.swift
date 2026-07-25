//
//  CouncilApp.swift
//  Council
//
//  Created by Joseph on 28.05.2026.
//

import CouncilKit
import SwiftUI
import Sparkle

/// One shared Sparkle updater for the app — started at launch so the background
/// schedule runs; Settings exposes the manual check + the auto toggle.
@MainActor
enum Updater {
    static let controller = SPUStandardUpdaterController(startingUpdater: true,
                                                         updaterDelegate: nil,
                                                         userDriverDelegate: nil)
}

@main
struct CouncilApp: App {
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
        }
        .windowStyle(.hiddenTitleBar)   // immersive, brutalist — content goes edge to edge
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1300, height: 820)
    }
}
