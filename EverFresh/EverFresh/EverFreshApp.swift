//
//  EverFreshApp.swift
//  EverFresh
//
//  Created by Maxwell  Peng  on 2026-09-13.
//

import SwiftUI

@main
struct EverFreshApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}
