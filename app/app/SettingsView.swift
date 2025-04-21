import SwiftUI

// Extracted view for Hardware specific settings
struct HardwareSettingsView: View {
    @ObservedObject var systemMonitor: SystemMonitor // Use ObservedObject since it's passed in
    private let customFont = "SpaceGrotesk-Regular" // Define font name

    var body: some View {
        // Keep vertical spacing for items within this tab
        VStack(alignment: .leading, spacing: 20) {
            Text("System Information")
                .font(.custom(customFont, size: 20)) // Apply custom font
                .fontWeight(.medium)
                .padding(.bottom, 5)
            
            // VRAM Display
            VStack(alignment: .leading, spacing: 5) {
                Text("Total GPU Memory (Unified/Dedicated)")
                    .font(.custom(customFont, size: 14)) // Apply custom font
                    .foregroundColor(.secondary)
                HStack {
                    if let vramMB = systemMonitor.totalVRAMMB {
                        let vramGB = vramMB / 1024.0 
                        Text(String(format: "%.1f GB", vramGB))
                            .font(.custom(customFont, size: 16).monospacedDigit()) // Apply custom font
                            .fontWeight(.semibold)
                    } else {
                        Text("Loading...")
                            .font(.custom(customFont, size: 16)) // Apply custom font
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                if systemMonitor.totalVRAMMB == nil {
                     ProgressView()
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 150) 
                }
            }
            .padding(.bottom, 10)

            // System CPU Usage Display
            VStack(alignment: .leading, spacing: 5) {
                Text("System CPU Usage")
                    .font(.custom(customFont, size: 14)) // Apply custom font
                    .foregroundColor(.secondary)
                HStack {
                    if let usage = systemMonitor.systemCPUUsage {
                        Text(String(format: "%.1f %%", usage * 100))
                            .font(.custom(customFont, size: 16).monospacedDigit()) // Apply custom font
                            .fontWeight(.semibold)
                    } else {
                        Text("Loading...")
                            .font(.custom(customFont, size: 16)) // Apply custom font
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                ProgressView(value: systemMonitor.systemCPUUsage ?? 0, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(cpuUsageColor(usage: systemMonitor.systemCPUUsage))
            }
             Spacer() // Push content to top within the tab
        }
        .padding() // Add padding within the tab content
    }
    
    // Moved cpuUsageColor helper here as it's only used by HardwareSettingsView
    private func cpuUsageColor(usage: Double?) -> Color {
        guard let usage = usage else { return .gray }
        if usage > 0.8 { return .red }
        if usage > 0.5 { return .orange }
        return .green
    }
}

struct SettingsView: View {
    @StateObject private var systemMonitor = SystemMonitor()
    @Environment(\.dismiss) var dismiss
    private let titleFont = "SpaceGrotesk-Bold" // Define font name for title
    private let customFont = "SpaceGrotesk-Regular" // Define font name for body

    var body: some View {
        VStack(alignment: .leading) { // Align main VStack leading for title
            // Add Settings Title
            Text("Settings")
                .font(.custom(titleFont, size: 28)) // Apply custom font and size
                .foregroundColor(.nuevoOrange) // Apply orange color
                .padding(.leading) // Add padding to align with tab content
                .padding(.top) // Add top padding

            TabView {
                HardwareSettingsView(systemMonitor: systemMonitor)
                    .tabItem {
                        Label("Hardware", systemImage: "cpu")
                    }
                
                Text("Preferences options coming soon...")
                    .font(.custom(customFont, size: 14)) // Apply custom font
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .tabItem {
                        Label("Preferences", systemImage: "gearshape.2")
                    }
            }
            // TabView takes available space
            
            // Close Button Section (remains at the bottom)
            HStack {
                Spacer()
                Button("Done") { 
                    dismiss() 
                }
                .font(.custom(customFont, size: 14)) // Apply custom font
                .tint(.nuevoOrange) 
                .buttonStyle(.borderedProminent) 
                .controlSize(.large) 
                .keyboardShortcut(.defaultAction)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom) // Add padding only to bottom for the button
        }
        // Remove padding from the outer VStack, let TabView and button handle their own
        .frame(minWidth: 400, minHeight: 400) // Adjusted minHeight for title
        .onAppear {
            systemMonitor.startMonitoring()
        }
        .onDisappear {
            systemMonitor.stopMonitoring()
        }
    }
    
    // cpuUsageColor moved to HardwareSettingsView
}

#Preview("SettingsView - Hardware Tab") {
    SettingsView()
        .preferredColorScheme(.dark)
}

#Preview("SettingsView - Preferences Tab") {
    // To preview the second tab, we might need a state variable
    // or just preview the content directly if simple.
    Text("Preferences options coming soon...")
        .padding()
        .frame(width: 300, height: 200)
} 