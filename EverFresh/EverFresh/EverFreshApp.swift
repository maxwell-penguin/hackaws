//
//  EverFreshApp.swift
//  EverFresh
//
//  Created by Maxwell  Peng  on 2026-09-13.
//

import SwiftUI
import UserNotifications

@main
struct EverFreshApp: App {
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Set before launch finishes so a notification delivered at launch is handled. The shared
        // instance keeps the delegate alive (the center only holds it weakly).
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        // Nav bars and tab bar are UIKit-drawn, so tokens go in via appearance proxies.
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(Color.enamel)
        nav.shadowColor = UIColor(Color.shelfSteel)
        let ink = UIColor(Color.compressor)
        nav.titleTextAttributes = [.foregroundColor: ink, .font: UIFont.systemFont(ofSize: 17, weight: .heavy)]
        nav.largeTitleTextAttributes = [.foregroundColor: ink, .font: UIFont.systemFont(ofSize: 34, weight: .heavy), .kern: -0.4]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(Color.enamel)
        tab.shadowColor = UIColor(Color.shelfSteel)
        for item in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            item.normal.iconColor = UIColor(Color.shelfSteel)
            item.normal.titleTextAttributes = [.foregroundColor: UIColor(Color.shelfSteel)]
            item.selected.iconColor = UIColor(Color.freezerUltramarine)
            item.selected.titleTextAttributes = [.foregroundColor: UIColor(Color.freezerUltramarine)]
        }
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .tint(.freezerUltramarine)
                .font(.everFreshBody)
                .foregroundStyle(Color.compressor)
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task {
                        await ReminderScheduler.shared.refreshAuthorizationStatus()
                        ReminderScheduler.shared.requestRefresh()
                    }
                }
        }
    }
}
