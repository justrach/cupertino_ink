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

## Next Steps / Ideas

- [ ] 
- [ ] 

## Prompting Notes

- Focus on how the SSE stream is processed in `ChatViewModel.processChatInteraction`.
- Note the change of `Message` from `struct` to `class` for UI updates.