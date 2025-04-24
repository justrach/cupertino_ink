# Memories

This file contains notes, ideas, and prompts for future development iterations or for instructing the next AI model.

## Session Summary (Current)

*   **Tool Management Refactoring:** Created `ToolRegistry.swift` to hold tool definitions (`availableToolsDict`) and the `AnyEncodable` helper struct, separating concerns from `ContentView.swift`.
*   **SSE Streaming Implementation:** Modified `ChatViewModel.processChatInteraction` to handle Server-Sent Events (SSE).
    *   Reads the stream line by line.
    *   Decodes JSON chunks (`SSEChunk`).
    *   Accumulates partial tool call information (`toolCallAccumulator`).
    *   Appends content deltas (`choice.delta.content`) directly to the message in the UI.
*   **Streaming UI Updates:** Updated `ChatView` and `Message`:
    *   Changed `Message` from `struct` to `class` conforming to `ObservableObject`, with `@Published var text`.
    *   Updated `MessageView` to use `@ObservedObject var message`.
    *   Ensured UI updates incrementally as text arrives by modifying the `@Published text` property on the main thread.
*   **Debugging:**
    *   Resolved duplicate `AnyEncodable` declaration errors after refactoring.
    *   Added detailed logging to diagnose SSE stream processing.
    *   Adapted finalization logic to handle local server streams ending with `[DONE]` but without a `finish_reason: "stop"`.
    *   Switched `Message` to a class to resolve UI update issues potentially related to struct value semantics.
*   **Code Structure Refactoring:** Split the large `ContentView.swift` into multiple files:
    *   `Models.swift`: Contains `Message`, API structs (`SSEChunk`, `ChatCompletionRequestBody`, etc.), `AnyEncodable`.
    *   `ChatViewModel.swift`: Contains the main view model logic, including SSE processing and tool execution.
    *   `ChatView.swift`, `MessageView.swift`, `ProcessingIndicatorView.swift`: Contain the respective SwiftUI views.
    *   `Utilities.swift`: Contains global constants (`baseURL`, `modelName`, `mockChatHistory`), extensions, and helper functions (`toggleSidebar`).
    *   `ToolRegistry.swift`: Primarily holds tool dictionary definitions (though `availableToolsDict` was temporarily moved to `Models.swift` during refactoring, ideally should reside here).
    *   `Color+Extensions.swift`: Holds the `Color` extension for custom app colors.
*   **Robust Tool Call Parsing:** Enhanced `ChatViewModel.processChatInteraction` to parse tool calls directly from the response text (`<tool_call>{...}</tool_call>`) using regex as a fallback if the `finish_reason` is not `"tool_calls"`. Added the `parseToolCallsFrom` helper function.
*   **Compiler Error Resolution:** Fixed various compiler errors in `ContentView.swift` related to `NSColor`, `ColorScheme`, and background modifiers resulting from the refactoring.
*   **Settings View Implementation:**
    *   Created `SettingsView.swift` presented as a sheet from `ContentView.swift`.
    *   Added a settings gear icon button pinned to the bottom-left of the `ContentView` sidebar using `.safeAreaInset`.
    *   Implemented system statistics fetching in `SystemMonitor.swift`:
        *   Fetches Total VRAM (using `IOKit`, handling Apple Silicon unified memory by reporting total system RAM).
        *   Fetches overall System CPU Usage (using `mach` host APIs).
        *   Includes periodic updates via `Timer` and fixes for compiler errors/warnings.
    *   Designed `SettingsView` UI:
        *   Displays VRAM (GB) and CPU Usage (%) with text and a `ProgressView`.
        *   Added a "Done" button (using app's orange theme color) to dismiss.
        *   Improved typography and layout.
    *   Refactored settings into tabs:
        *   Created `HardwareSettingsView` to encapsulate hardware stats.
        *   Used `TabView` in `SettingsView` with "Hardware" and placeholder "Preferences" tabs.
*   **Color Definitions:**
    *   Established custom colors in `Color+Extensions.swift`.
    *   Primary Accent: `nuevoOrange = Color(red: 1.0, green: 0.3, blue: 0.1)` used for interactive elements (e.g., Settings Done button).
    *   Main Background: Dynamically set in `ContentView.swift` based on system `colorScheme` (`Color.black` for dark, `NSColor.windowBackgroundColor` for light).
    *   Other custom grays also defined (`nuevoDarkGray`, `nuevoLightGray`, etc.).
*   **UI Refinements:**
    *   Applied "Space Grotesk" font (Regular and Bold) to `SettingsView` title and text elements.
    *   Added a main "Settings" title (using `nuevoOrange`) to the top-left of the settings sheet.
    *   Relocated Chat Search:
        *   Moved search functionality from top toolbar to the sidebar.
        *   Implemented using a manually placed `TextField` above the chat list.
        *   Styled with `.textFieldStyle(.roundedBorder)` for standard appearance.
    *   Added Model Picker (`fast`/`medium`/`slow`) to the top toolbar's primary actions area.
    *   Implemented Custom Title Bar:
        *   Initially tried hiding system title bar and adding a custom SwiftUI view.
        *   Refactored to use `.windowStyle(.hiddenTitleBar)` and integrated custom title ("cupertino.ink" in orange) and sidebar toggle directly into `NavigationView` toolbar (`.principal` and `.navigation` placements) for correct layout.
*   **System Prompt Generalization:** Modified the `systemPrompt` in `ChatViewModel.swift` to allow for general conversation and direct answers, while still defining specific tool usage guidelines.

## Next Steps / Ideas

- [ ] **Explore Model Context Protocol (MCP):** Investigate replacing the current hardcoded tool dictionaries (`findOrderToolDict`, etc.) and manual tool execution logic in `ChatViewModel` with MCP.
    - Define tools using the MCP schema.
    - Implement an MCP server or adapter within the app to handle tool execution requests from the model.
    - This could lead to a more modular and potentially standardized way of handling tools/functions.
- [ ] Add actual preferences to the "Preferences" tab in Settings.
- [ ] Implement search/filtering for chat history items.

## Prompting Notes

- Focus on how the SSE stream is processed in `ChatViewModel.processChatInteraction`.
- Note the change of `Message` from `struct` to `class` for UI updates.