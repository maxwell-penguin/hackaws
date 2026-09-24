//
//  ContentView.swift
//  EverFresh
//
//  Created by Maxwell  Peng  on 2026-09-13.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        MainTabView()
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
