import SwiftUI

struct ChatView: View {
    // Removed binding for sidebar visibility
    @Environment(\.colorScheme) var colorScheme // Detect light/dark mode
    // Use the ViewModel
    @StateObject private var viewModel: ChatViewModel
    
    // Optional: Receive history item to potentially load chat
    var historyItem: ChatHistoryItem? = nil

    // Initializer to handle ChatViewModel creation/injection
    init(historyItem: ChatHistoryItem? = nil) {
        self.historyItem = historyItem
        // Create a new ViewModel instance for this view
        // In a real app, you might pass this in or use @EnvironmentObject
        _viewModel = StateObject(wrappedValue: ChatViewModel())
        // TODO: Load initial messages based on historyItem if needed
    }

    var body: some View {
        VStack(spacing: 0) { // Remove spacing between ScrollView and Input area
            ScrollViewReader { proxy in // Add ScrollViewReader
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) { // Use LazyVStack for performance
                        ForEach(viewModel.messages) { message in
                            // Conditional View Rendering
                            if message.text == "[Processing Tools...]" {
                                ProcessingIndicatorView()
                                    .id(message.id) // Keep ID for scrolling
                            } else {
                                MessageView(message: message)
                                    .id(message.id) // Keep ID for scrolling
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top) // Add padding at the top of the messages list
                }
                // Set background based on color scheme
                .background(colorScheme == .dark ? Color.black : Color(NSColor.windowBackgroundColor))
                // Use viewModel.messages
                .onChange(of: viewModel.messages) { oldValue, newValue in // Observe the whole array for changes
                    // Ensure scrolling happens only when count increases and the last message is new
                    if newValue.count > oldValue.count, let lastMessage = newValue.last {
                        scrollToBottom(proxy: proxy, messageId: lastMessage.id)
                    }
                }
                .onAppear { // Scroll to bottom on initial appear
                   // Use viewModel.messages
                   scrollToBottom(proxy: proxy, messageId: viewModel.messages.last?.id)
                }
            }

            // Input area
            HStack(spacing: 10) { // Container for TextField and Button
                // Use viewModel.newMessageText
                TextField("Ask anything...", text: $viewModel.newMessageText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .frame(minHeight: 30)
                    // Remove specific TextField styling (background, clip, overlay)
                    .foregroundColor(colorScheme == .dark ? .nuevoLightGray : .primary)
                    .onSubmit { // Call ViewModel's sendMessage
                        viewModel.sendMessage()
                    }
                    .disabled(viewModel.isSending) // Disable while sending

                Button(action: viewModel.sendMessage) { // Call ViewModel's sendMessage
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        // Use nuevoOrange when enabled, slightly dimmer/grayer when disabled
                        .foregroundColor(viewModel.newMessageText.isEmpty || viewModel.isSending ? .gray.opacity(0.6) : .nuevoOrange)
                }
                .buttonStyle(.plain)
                 // Use viewModel properties for disabled state
                .disabled(viewModel.newMessageText.isEmpty || viewModel.isSending)
                .frame(minHeight: 30) // Align height with TextField
            }
            // Apply styling to the HStack to create the 'island'
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            // Set background based on color scheme
            .background(colorScheme == .dark ? Color.nuevoInputBackground : Color(white: 0.95))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    // Set stroke based on color scheme
                    .stroke(colorScheme == .dark ? Color.nuevoStroke : Color.gray.opacity(0.2), lineWidth: 1)
            )
            .padding(.horizontal, 20) // Padding outside the island for centering
            .padding(.bottom, 10) // Padding below the island
            .frame(maxWidth: 800) // Keep the max width constraint
        }
        // Set the background of the entire VStack based on color scheme
        .background(colorScheme == .dark ? Color.black : Color(NSColor.windowBackgroundColor))
        // Use the selected chat title if available, otherwise default
        .navigationTitle(historyItem?.title ?? "cupertino.ink")
    }

    // Helper function to scroll to the bottom
    private func scrollToBottom(proxy: ScrollViewProxy, messageId: UUID?) {
        guard let id = messageId else { return }
        withAnimation(.easeOut(duration: 0.25)) { // Add animation
             proxy.scrollTo(id, anchor: .bottom)
        }
    }
} 