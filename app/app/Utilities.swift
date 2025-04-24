import SwiftUI
import Foundation

// --- Mock Data ---
let mockChatHistory: [ChatHistoryItem] = [
    ChatHistoryItem(title: "Understanding OLAP da..."),
    ChatHistoryItem(title: "Top 100 Restaurants JSON"),
    ChatHistoryItem(title: "Old Age Realization"),
    ChatHistoryItem(title: "lldb-rpc-server Explanation"),
    ChatHistoryItem(title: "Alzheimer's Memory Aide Proj..."),
    ChatHistoryItem(title: "DYLD Library Missing Fix"),
    ChatHistoryItem(title: "App idea generation"),
    ChatHistoryItem(title: "Quasar and Person"),
    ChatHistoryItem(title: "Futuristic Cartoon Request"),
    ChatHistoryItem(title: "iOS Simulator Runtime issue")
]

// --- API Configuration ---
let baseURL = "http://127.0.0.1:10240/v1/chat/completions"
let modelName = "lmstudio-community/Qwen2.5-7B-Instruct-MLX-4bit" // Your model

// --- Helper Extensions ---

// Helper extension for checking whitespace
extension String {
    var containsWhitespace: Bool {
        return self.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
    }
}

// --- Global Helper Functions ---

// Helper function to call the standard toggleSidebar action (macOS)
func toggleSidebar() {
    #if os(macOS)
    NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
    #endif
} 