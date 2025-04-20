import SwiftUI

// --- ADD New View for Processing Indicator ---
struct ProcessingIndicatorView: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small) // Make the spinner smaller
                .colorMultiply(colorScheme == .dark ? .nuevoLightGray : .primary) // Match text color
            Text("[Processing Tools...]")
                .font(.body)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        // Apply same styling as bot messages
        .background(colorScheme == .dark ? Color.nuevoDarkGray : Color(white: 0.9))
        .foregroundColor(colorScheme == .dark ? .nuevoLightGray : .primary)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading) // Align to left like bot messages
        .padding(.horizontal) // Add horizontal padding like MessageView's container does
    }
} 