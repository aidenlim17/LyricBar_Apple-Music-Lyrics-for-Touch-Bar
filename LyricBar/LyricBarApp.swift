//
//  LyricBarApp.swift
//  LyricBar
//
//  Created by aiden on 7/12/26.
//

import SwiftUI

@main
struct LyricBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = LyricBarViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .onAppear {
                    appDelegate.configure(viewModel: viewModel)
                }
        }
    }
}
