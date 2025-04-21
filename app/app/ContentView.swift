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
    private let titleFont = "SpaceGrotesk-Bold"
    
    // State for model selection
    @State private var selectedModel: String = "medium"
    let models = ["fast", "medium", "slow"]

    var body: some View {
        ZStack { // ZStack remains for background
            // Apply background conditionally directly within the ZStack
            if colorScheme == .dark {
                Color.black.ignoresSafeArea()
            } else {
                Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            }
            
            NavigationView {
                // Sidebar List
                List {
                   // Manually add TextField above the Section
                   TextField("Search Chats", text: $searchText)
                       .textFieldStyle(.roundedBorder) // Restore standard border style
                       .padding(.horizontal, 8) 
                       .padding(.vertical, 5) 
                       .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                       // No custom background 
                    
                   Section("Chats") {
                        ForEach(filteredChats) { chat in
                            NavigationLink(destination: ChatView(historyItem: chat)) { 
                                 Text(chat.title)
                                     .lineLimit(1)
                            }
                        }
                    }
                }
                .listStyle(.sidebar) 
                // Set sidebar navigation title (it won't show in title bar now)
                // but might be used for accessibility or other contexts.
                .navigationTitle("History") 
                .safeAreaInset(edge: .bottom) { 
                    // Settings button remains pinned at the bottom
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .padding(8) 
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 8) 
                    .frame(maxWidth: .infinity, alignment: .leading) 
                }
                
                // Detail View
                ChatView() 
            }
            .sheet(isPresented: $showingSettings) { 
                SettingsView()
            }
            .toolbar { 
                // --- Toolbar Customization --- 
                
                // Sidebar Toggle (Leading)
                ToolbarItem(placement: .navigation) { 
                    Button(action: toggleSidebar) { 
                        Label("Toggle Sidebar", systemImage: "sidebar.left")
                    }
                    .keyboardShortcut("t", modifiers: .command) // Example shortcut
                }
                
                // Custom Title (Center)
                ToolbarItem(placement: .principal) {
                    Text("cupertino.ink")
                         .font(.custom(titleFont, size: 16))
                         .foregroundColor(.nuevoOrange)
                        // Note: Dragging should work on the window frame provided by
                        // the system when using .hiddenTitleBar, even without the text.
                        // If dragging is lost, we might need to revisit WindowDragView 
                        // as an overlay on this Text or the whole toolbar content.
                }
                
                // Search Field & Model Picker (Trailing)
                ToolbarItemGroup(placement: .primaryAction) {
                    // Remove Search Field from here
                    // TextField("Search Chats", text: $searchText)
                    //     .textFieldStyle(.roundedBorder)
                    //     .frame(width: 150) 
                        
                    // Model Picker
                    Picker("Model", selection: $selectedModel) {
                        ForEach(models, id: \.self) { modelName in
                            Text(modelName).tag(modelName)
                        }
                    }
                    .pickerStyle(.menu) 
                }
            }
            // Opacity and onAppear applied to the ZStack content
            .opacity(contentVisible ? 1 : 0)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        contentVisible = true
                    }
                }
            }
        }
        // Frame applied to the ZStack (outermost view now)
        .frame(minWidth: 600, minHeight: 400) 
        // No longer need .ignoresSafeArea(.top) here
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
