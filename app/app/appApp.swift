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
                    .transition(.opacity) // Fade transition for the splash screen vieimage.pngw
                } else {
                    ContentView() // Show main content
                         .transition(.opacity) // Fade transition for the content view
                }
            }
        }
    }
}
