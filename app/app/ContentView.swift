//
//  ContentView.swift
//  app
//
//  Created by Rach Pradhan on 4/18/25.
//

import SwiftUI

// Define a structure for chat messages
struct Message: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isUser: Bool // To differentiate user messages (could be used for styling)
}

// Define a structure for mock chat history
struct ChatHistoryItem: Identifiable {
    let id = UUID()
    let title: String
}

// Mock Data
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

struct ContentView: View {
    // State for search text
    @State private var searchText = ""
    // State to manage chat history filtering (if implementing search)
    // @State private var filteredChatHistory = mockChatHistory
    @State private var contentVisible = false // State for fade-in

    var body: some View {
        ZStack { // Wrap in ZStack for fade-in from black
            // Background that starts as black
            Color.black.edgesIgnoringSafeArea(.all)

            // Your existing NavigationView
            NavigationView {
                // Sidebar - Always present in the structure for NavigationView to manage
                List {
                    // Removed the top Section with "New Chat" Label

                    // Section for chat history
                    Section("Chats") {
                        // TODO: Replace mockChatHistory with filtered list if implementing search
                        ForEach(mockChatHistory) { chat in
                            // No longer need to pass binding
                            NavigationLink(destination: ChatView(historyItem: chat)) { 
                                 Text(chat.title)
                                     .lineLimit(1)
                            }
                        }
                    }
                }
                .listStyle(.sidebar) 
                .navigationTitle("History") 
                // Add search functionality to the List
                .searchable(text: $searchText, prompt: "Search Chats")
                
                // Detail View (Placeholder or initial view)
                // No longer need to pass binding
                ChatView()
            }
            // Add the main toolbar to the NavigationView
            .toolbar {
                // Group buttons for better layout control if needed
                ToolbarItemGroup(placement: .navigation) { // Primary actions group
                     Button {
                        // Use the standard macOS action to toggle the sidebar
                        toggleSidebar()
                    } label: {
                        Image(systemName: "sidebar.left")
                    }
                    
                    Button {
                        // Placeholder action for creating a new chat
                        print("New Chat button tapped")
                        // TODO: Implement new chat logic
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .frame(minWidth: 600, minHeight: 400)
            // Apply fade-in effect to the NavigationView
            .opacity(contentVisible ? 1 : 0)
            .background( // Set the actual background color of the content area
                 // Use system background for adaptability, but it will fade in over black
                 Color(NSColor.windowBackgroundColor)
            )
        }
        // Add onAppear to trigger the fade-in
        .onAppear {
            // Add a very short delay before starting the fade-in
            // to ensure the black background is present first.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.easeInOut(duration: 0.6)) {
                    contentVisible = true
                }
            }
        }
    }
}

struct ChatView: View {
    // Removed binding for sidebar visibility
    
    // Optional: Receive history item to potentially load chat
    var historyItem: ChatHistoryItem? = nil

    // State variables to hold messages and user input
    @State private var messages: [Message] = [
        // Example messages (can be removed or loaded based on historyItem)
        Message(text: "Hello! How can I help you today?", isUser: false),
        Message(text: "Hi! What can you do?", isUser: true)
    ]
    @State private var newMessageText: String = ""

    var body: some View {
        VStack(spacing: 0) { // Remove spacing between ScrollView and Input area
            // Scrollable view for messages
            ScrollViewReader { proxy in // Add ScrollViewReader
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) { // Use LazyVStack for performance
                        ForEach(messages) { message in
                            MessageView(message: message)
                                .id(message.id) // Add ID for scrolling
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top) // Add padding at the top of the messages list
                }
                // Set background of the scrollable content area to the system window background color
                .background(Color(NSColor.windowBackgroundColor))
                .onChange(of: messages) { oldValue, newValue in // Observe the whole array for changes
                    // Ensure scrolling happens only when count increases and the last message is new
                    if newValue.count > oldValue.count, let lastMessage = newValue.last { 
                        scrollToBottom(proxy: proxy, messageId: lastMessage.id)
                    }
                }
                .onAppear { // Scroll to bottom on initial appear
                   scrollToBottom(proxy: proxy, messageId: messages.last?.id)
                }
            }

            // Input area
            HStack(spacing: 10) { // Container for TextField and Button
                TextField("Ask anything...", text: $newMessageText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .frame(minHeight: 30)
                    // Remove specific TextField styling (background, clip, overlay)

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(newMessageText.isEmpty ? .gray.opacity(0.5) : .blue)
                }
                .buttonStyle(.plain)
                .disabled(newMessageText.isEmpty)
                .frame(minHeight: 30) // Align height with TextField
            }
            // Apply styling to the HStack to create the 'island'
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
            .padding(.horizontal, 20) // Padding outside the island for centering
            .padding(.bottom, 10) // Padding below the island
            .frame(maxWidth: 800) // Keep the max width constraint
        }
        // Set the background of the entire VStack to the system window background color
        .background(Color(NSColor.windowBackgroundColor))
        // Use the selected chat title if available, otherwise default
        .navigationTitle(historyItem?.title ?? "Chatbot")
    }

    // Function to handle sending a message
    func sendMessage() {
        guard !newMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let userMessage = Message(text: newMessageText, isUser: true)
        newMessageText = "" // Clear text field immediately

        withAnimation(.easeOut(duration: 0.15)) {
            messages.append(userMessage)
        }

        // Placeholder bot response
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let thinkingMessage = Message(text: "Thinking...", isUser: false)
            withAnimation(.easeOut(duration: 0.15)) {
                 messages.append(thinkingMessage)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                 let responseText = "This is a placeholder response to your query about: \"\(userMessage.text)\""
                 let responseMessage = Message(text: responseText, isUser: false)
                 if let index = messages.firstIndex(where: { $0.id == thinkingMessage.id }) {
                      withAnimation(.easeOut(duration: 0.2)) {
                          messages[index] = responseMessage
                      }
                 } else {
                     withAnimation(.easeOut(duration: 0.15)) {
                         messages.append(responseMessage)
                     }
                 }
            }
        }
    }

    // Helper function to scroll to the bottom
    private func scrollToBottom(proxy: ScrollViewProxy, messageId: UUID?) {
        guard let id = messageId else { return }
        proxy.scrollTo(id, anchor: .bottom)
    }
}

// Separate View for Message Bubble Styling
struct MessageView: View {
    let message: Message

    var body: some View {
        HStack {
            if message.isUser {
                Spacer() // Push user messages to the right
            }

            VStack(alignment: message.isUser ? .trailing : .leading) {
                 Text(message.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    // Use gray with opacity for a light background, compatible across versions
                    .background(message.isUser ? Color.blue : Color.gray.opacity(0.1))
                    .foregroundColor(message.isUser ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous)) // Nicer rounding
                    // Add specific corner masking if needed for 'tail' effect (more complex)
            }
            .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading) // Ensure HStack fills width for alignment

            if !message.isUser {
                Spacer() // Push bot messages to the left
            }
        }
    }
}

// Helper function to call the standard toggleSidebar action (macOS)
private func toggleSidebar() {
    #if os(macOS)
    NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
    #endif
}

#Preview {
    // Preview the main ContentView which now includes the sidebar
    ContentView()
}
