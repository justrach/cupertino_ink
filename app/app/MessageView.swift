import SwiftUI
import AppKit // Needed for NSPasteboard on macOS

// Separate View for Message Bubble Styling
struct MessageView: View {
    @ObservedObject var message: Message // Now takes ObservableObject
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) { // Align items at the bottom, add spacing
            if message.isUser {
                Spacer() // Push user messages to the right
            }

            // Message Content Bubble
            VStack(alignment: message.isUser ? .trailing : .leading) {
                 Text(message.text) // SwiftUI Text handles basic Markdown
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    // Use new color scheme for messages, adapting to light/dark mode
                    .background(message.isUser ? Color.nuevoOrange : (colorScheme == .dark ? Color.nuevoDarkGray : Color(white: 0.9)))
                    .foregroundColor(message.isUser ? .white : (colorScheme == .dark ? .nuevoLightGray : .primary))
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous)) // Nicer rounding
                    .contextMenu { // Add context menu for copying
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(message.text, forType: .string)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    }
            }
            .frame(maxWidth: (NSScreen.main?.visibleFrame.width ?? 1024) * 0.75, alignment: message.isUser ? .trailing : .leading) // Limit message width using NSScreen, ensure alignment

            // Copy Button (conditionally shown for non-empty bot messages)
            if !message.isUser && !message.text.isEmpty {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message.text, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.gray)
                }
                .buttonStyle(PlainButtonStyle()) // Remove default button styling
                .padding(.bottom, 5) // Align better with text baseline
            }

            if !message.isUser {
                Spacer() // Push bot messages and copy button to the left
            }
        }
        // Add padding to the entire HStack row
        .padding(.horizontal)
        .padding(.vertical, 4) // Add a little vertical padding between messages
    }
} 