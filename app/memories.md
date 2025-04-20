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

## Next Steps / Ideas

- [ ] 
- [ ] 

## Prompting Notes

- Focus on how the SSE stream is processed in `ChatViewModel.processChatInteraction`.
- Note the change of `Message` from `struct` to `class` for UI updates.