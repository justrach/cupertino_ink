//
//  ContentView.swift
//  app
//
//  Created by Rach Pradhan on 4/18/25.
//

import SwiftUI
import AppKit // <-- Add AppKit import for NSColor
// Removed: Combine, Foundation, OpenAI (already removed)

// --- All models moved to Models.swift ---
// --- Mock Chat History moved to Utilities.swift ---
// --- API Structs moved to Models.swift ---
// --- API Config moved to Utilities.swift ---
// --- Tool Definitions moved to Models.swift (temporarily, will move later) ---
// --- Helper String extension moved to Utilities.swift ---
// --- ParsedToolCall struct moved to Models.swift ---
// --- ChatViewModel moved to ChatViewModel.swift ---

struct ContentView: View {
    // State for search text
    @State private var searchText = ""
    // State to manage chat history filtering (if implementing search)
    // @State private var filteredChatHistory = mockChatHistory // Use mockChatHistory from Utilities.swift
    @State private var contentVisible = false // State for fade-in - RESTORED
    @Environment(\.colorScheme) var colorScheme // Detect light/dark mode
    @State private var showingSettings = false // State for presenting the Settings sheet

    var body: some View {
        // REMOVED background color variable definition
        // let backgroundColor = colorScheme == .dark ? Color.black : Color(nsColor: NSColor.windowBackgroundColor)
        
        ZStack {
            // Apply background conditionally directly within the ZStack
            if colorScheme == .dark {
                Color.black.ignoresSafeArea()
            } else {
                Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            }
            
            NavigationView {
                // Sidebar
                List {
                    // Put Section directly back into List
                    // VStack removed
                    Section("Chats") {
                        ForEach(filteredChats) { chat in
                            NavigationLink(destination: ChatView(historyItem: chat)) { 
                                 Text(chat.title)
                                     .lineLimit(1)
                            }
                        }
                    }
                    // Spacer and Button moved to safeAreaInset below
                }
                .listStyle(.sidebar) 
                .navigationTitle("History") 
                .searchable(text: $searchText, prompt: "Search Chats")
                .safeAreaInset(edge: .bottom) { // Pin button to bottom
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .padding(8) // Add some padding around the icon for easier tapping
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 8) // Add padding from the left edge
                    .frame(maxWidth: .infinity, alignment: .leading) // Force to left
                }
                
                // Detail View
                ChatView() 
            }
            .sheet(isPresented: $showingSettings) { 
                SettingsView()
            }
            .toolbar { // Add toolbar for the toggle button
                ToolbarItem(placement: .navigation) { // Place it near the trailing edge/primary actions
                    Button(action: toggleSidebar) { // toggleSidebar is now in Utilities.swift
                        Label("Toggle Sidebar", systemImage: "sidebar.left")
                    }
                }
            }
            .frame(minWidth: 600, minHeight: 400)
            .opacity(contentVisible ? 1 : 0)
        }
        // Add onAppear to trigger the fade-in - RESTORED
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.easeInOut(duration: 0.6)) {
                    contentVisible = true
                }
            }
        }
    }

    // Computed property to filter chat history based on search text
    private var filteredChats: [ChatHistoryItem] {
        if searchText.isEmpty {
            return mockChatHistory // Use global constant from Utilities.swift
        } else {
            return mockChatHistory.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }
    }
}

// --- ChatView moved to ChatView.swift ---
// --- MessageView moved to MessageView.swift ---
// --- ProcessingIndicatorView moved to ProcessingIndicatorView.swift ---
// --- toggleSidebar moved to Utilities.swift ---

#Preview {
    // Preview the main ContentView which now includes the sidebar
    ContentView()
        // Remove preferred color scheme to see both light and dark previews
}

// --- Color Definitions moved to Models.swift ---
// (Keeping them in Models for now, could move to a dedicated Theme file later)
