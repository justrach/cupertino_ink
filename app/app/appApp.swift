//
//  appApp.swift
//  app
//
//  Created by Rach Pradhan on 4/18/25.
//

import SwiftUI

@main
struct appApp: App {
    @State private var showSplashScreen = true // State to control splash screen visibility
    @StateObject private var mcpHost = MCPHost() // Create the MCPHost instance

    var body: some Scene {
        WindowGroup {
            ZStack { // Use ZStack to manage the transition
                if showSplashScreen {
                    SplashScreenView { // Show splash screen
                        // When finished, update the state to hide splash screen
                        withAnimation(.easeInOut(duration: 0.5)) { // Smooth transition
                            showSplashScreen = false
                        }
                    }
                    .transition(.opacity) // Fade transition for the splash screen view
                } else {
                    ContentView()
                        .environmentObject(mcpHost) // Pass MCPHost down the view hierarchy
                        .task { // Start MCP host when ContentView appears
                            await mcpHost.start()
                        }
                         .transition(.opacity) // Fade transition for the content view
                }
            }
            // It's generally better to handle cleanup at the app level if possible,
            // but .task on ContentView is a common pattern. Consider AppDelegate/SceneDelegate for more robust cleanup.
            // .onDisappear { // Example: Stop MCP host (might not always be called reliably)
            //     Task { await mcpHost.stop() }
            // }
        }
        .windowStyle(.hiddenTitleBar) // Hide the standard title bar
    }
}
