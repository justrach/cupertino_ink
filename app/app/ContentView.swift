//
//  ContentView.swift
//  app
//
//  Created by Rach Pradhan on 4/18/25.
//

import SwiftUI
import Combine // Still needed for ObservableObject
// Removed: import OpenAI
import Foundation // Needed for URLSession, JSONEncoder/Decoder etc.

// Define a structure for chat messages
// Change to class conforming to ObservableObject
class Message: Identifiable, ObservableObject, Equatable {
    let id: UUID
    @Published var text: String // Mark text as Published
    let isUser: Bool
    
    init(id: UUID = UUID(), text: String, isUser: Bool) {
        self.id = id
        self.text = text
        self.isUser = isUser
    }

    // Equatable conformance remains the same (based on ID)
    static func == (lhs: Message, rhs: Message) -> Bool {
        lhs.id == rhs.id
    }
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

// --- API Request/Response Structs (Encodable) ---

// Matches the structure needed for the API request body
struct ChatCompletionRequestBody: Encodable {
    let model: String
    let messages: [[String: AnyEncodable]]
    let tools: [[String: AnyEncodable]]?
    let tool_choice: String?
    let stream: Bool
    // Add other parameters like temperature if needed
}

// Represents the overall structure of an SSE data chunk
struct SSEChunk: Decodable {
    let id: String? // Optional ID
    let choices: [SSEChoice]?
}

// Represents a choice within an SSE chunk
struct SSEChoice: Decodable {
    let delta: SSEDelta
    let finish_reason: String? // e.g., "stop", "tool_calls"
}

// Represents the delta content within a choice
struct SSEDelta: Decodable {
    let role: String? // e.g., "assistant"
    let content: String?
    let tool_calls: [ToolCallChunk]?
}

// Represents a tool call chunk (might be partial)
struct ToolCallChunk: Decodable {
    let index: Int
    let id: String? // ID might come in the first chunk
    let type: String? // e.g., "function"
    let function: FunctionCallChunk? // Function details
}

// Represents the function call part (might be partial)
struct FunctionCallChunk: Decodable {
    let name: String? // Name might come first
    let arguments: String? // Arguments might come in subsequent chunks
}

// Represents a fully assembled tool call after processing the stream
struct AssembledToolCall: Identifiable {
    let index: Int
    let id: String
    let functionName: String
    let arguments: String // Accumulated arguments JSON string
}

// Helper Structs for JSON Decoding
struct ToolCallArgsFindOrder: Decodable {
    let customer_name: String
}

struct ToolCallArgsGetDelivery: Decodable {
    let order_id: String
}

// --- API Configuration ---
let baseURL = "http://127.0.0.1:10240/v1/chat/completions"
let modelName = "mlx-community/Qwen2.5-7B-Instruct-1M-4bit" // Your model

// --- Tool Definitions (Simple Dictionaries) ---
// Matches the API structure: https://platform.openai.com/docs/api-reference/chat/create#chat-create-tools
// ... existing code ...

// Helper extension for checking whitespace
extension String {
    var containsWhitespace: Bool {
        return self.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
    }
}

// Re-add necessary structs for parsing
struct ParsedToolCall {
    let id: String = "call_\(UUID().uuidString.prefix(12))"
    let type: String = "function"
    let function: FunctionCall
    struct FunctionCall {
        let name: String
        let arguments: [String: String]
    }
}

// --- Chat View Model ---
@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = [
        // Initial message or load from history
        Message(text: "Hello! How can I help you today?", isUser: false)
    ]
    @Published var newMessageText: String = ""
    @Published var isSending: Bool = false // To disable input while processing

    private var currentTask: Task<Void, Never>? = nil
    let systemPrompt = """
    You are a helpful customer support assistant focused on order delivery dates.
    Follow these steps precisely:
    1. Greet the user. If they ask about their order/delivery without providing details, ask for their *full name*. Do not ask for the order ID.
    2. When the user provides a name, use the `find_order_by_name` tool. Do not guess or assume the name is correct.
    3. If `find_order_by_name` returns an `order_id`, immediately use the `get_delivery_date` tool with that specific ID.
    4. If `find_order_by_name` returns no `order_id` (null or missing), inform the user politely that the order could not be found and ask them to verify the name or provide an order ID if they have one.
    5. Relay the estimated delivery date from `get_delivery_date` clearly to the user.
    6. If any tool call results in an error, inform the user about the issue based on the error message.
    Focus only on fulfilling the request using the tools. Be concise. Respond naturally.
    """

    // Corrected History Type: Use [String: Any] to allow complex values like tool_calls
    private var messageHistory: [[String: Any]] = []

    init() {
        messageHistory.append(["role": "system", "content": systemPrompt])
    }

    func sendMessage() {
        guard !newMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isSending else { return }
        let userMessageText = newMessageText
        newMessageText = ""
        isSending = true
        let userMessage = Message(text: userMessageText, isUser: true)
        messages.append(userMessage)
        // Add user message - value is String, compatible with [String: Any]
        messageHistory.append(["role": "user", "content": userMessageText])

        currentTask?.cancel()
        currentTask = Task {
            await processChatInteraction()
            if !Task.isCancelled { isSending = false }
        }
    }
    
    private func processChatInteraction() async {
        var shouldContinueLoop = true
        let jsonEncoder = JSONEncoder()
        let jsonDecoder = JSONDecoder()

        while shouldContinueLoop && !Task.isCancelled {
            shouldContinueLoop = false
            let botResponsePlaceholderId = UUID()
            await MainActor.run { // Ensure placeholder is added on main thread before await
                 messages.append(Message(id: botResponsePlaceholderId, text: "", isUser: false))
            }

            // Add logging for history before API call
            print("--- History Before API Call (Turn Start) ---")
            do {
                 let historyData = try JSONSerialization.data(withJSONObject: messageHistory, options: .prettyPrinted)
                 print(String(data: historyData, encoding: .utf8) ?? "Failed to print history")
            } catch { print("Error printing history: \(error)") }
            print("-------------------------------------------")

            let messagesForRequest = messageHistory.map { dict -> [String: AnyEncodable] in
                 dict.mapValues { AnyEncodable($0) }
            }
            let requestBody = ChatCompletionRequestBody(
                model: modelName,
                messages: messagesForRequest,
                tools: availableToolsDict,
                tool_choice: "auto",
                stream: true
            )
            guard let url = URL(string: baseURL) else { 
                let errorText = "Error: Invalid API URL"
                print(errorText)
                await MainActor.run {
                    if let index = messages.firstIndex(where: { $0.id == botResponsePlaceholderId }) {
                        messages[index].text = errorText
                    } else { messages.append(Message(text: errorText, isUser: false)) }
                }
                isSending = false
                return
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            
            do {
                request.httpBody = try jsonEncoder.encode(requestBody)
            } catch {
                let errorText = "Error: Failed to encode request: \(error.localizedDescription)"
                print(errorText)
                await MainActor.run {
                    if let index = messages.firstIndex(where: { $0.id == botResponsePlaceholderId }) {
                        messages[index].text = errorText
                    } else { messages.append(Message(text: errorText, isUser: false)) }
                }
                isSending = false
                return
            }

            // No longer accumulate full response here: var accumulatedResponse = ""
            var finalFinishReason: String? = nil
            // --- Tool Call Accumulation ---
            var toolCallAccumulator: [Int: (id: String?, name: String?, arguments: String)] = [:] // Index -> Partial Tool Call

            do {
                 print("--- Starting API Call (Turn) ---")
                 let (bytes, response) = try await URLSession.shared.bytes(for: request)
                
                 guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                     let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                     // Attempt to read error body
                     var errorBody = ""
                     // This part is tricky with streams, might not get full body easily
                     // try await bytes.lines.reduce(into: "") { $0 += $1 }
                     throw NSError(domain: "HTTPError", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP Error: \(statusCode). Body: \(errorBody)"]) // Simple error
                 }

                // Process the stream line by line
                for try await line in bytes.lines {
                    print("[SSE Raw Line]: \(line)") // Corrected syntax
                    guard !Task.isCancelled else { throw CancellationError() }
                    if line.hasPrefix("data:") {
                        let dataString = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        print("[SSE Data String]: \(dataString)") // Corrected syntax
                        guard let data = dataString.data(using: .utf8), !data.isEmpty else { continue }
                        if String(data: data, encoding: .utf8) == "[DONE]" {
                             print("[SSE Signal]: Received [DONE]")
                             break
                        }
                        
                        do {
                            let chunk = try jsonDecoder.decode(SSEChunk.self, from: data)
                            print("[SSE Decoded Chunk]: \(chunk)") // Corrected syntax
                            if let choice = chunk.choices?.first {
                                print("[SSE Decoded Delta]: \(choice.delta)") // Corrected syntax
                                // Store finish reason when available
                                if let reason = choice.finish_reason { finalFinishReason = reason }

                                // -- Handle Content Delta --
                                if let contentDelta = choice.delta.content, !contentDelta.isEmpty {
                                    await MainActor.run {
                                        if let index = messages.firstIndex(where: { $0.id == botResponsePlaceholderId }) {
                                            // Now that Message is a class and text is @Published,
                                            // directly modifying the property should trigger UI update.
                                            messages[index].text += contentDelta 
                                        } else {
                                            print("Error: Could not find placeholder message ID \(botResponsePlaceholderId) to stream content.")
                                        }
                                    }
                                }

                                // -- Handle Tool Call Deltas --
                                if let toolCallChunks = choice.delta.tool_calls {
                                     for chunk in toolCallChunks {
                                        let index = chunk.index
                                        // Get or create the accumulator entry
                                        var currentCall = toolCallAccumulator[index] ?? (id: nil, name: nil, arguments: "")

                                        if let id = chunk.id { currentCall.id = id }
                                        if let function = chunk.function {
                                            if let name = function.name { currentCall.name = name }
                                            if let argsChunk = function.arguments { currentCall.arguments += argsChunk }
                                        }
                                        toolCallAccumulator[index] = currentCall
                                    }
                                }
                            }
                        } catch { print("SSE Decode Error: \(error) for data: \(String(data: data, encoding: .utf8) ?? "invalid utf8")") }
                    }
                }
                print("Stream processing finished. Final Reason: \(finalFinishReason ?? "N/A")")

            } catch is CancellationError {
                 print("Task Cancelled during stream.")
                 shouldContinueLoop = false // Ensure loop terminates if cancelled
            } catch { // Handle URLSession errors, HTTP errors, etc.
                 print("Network/Stream Error: \(error)")
                 let errorText = "Error: \(error.localizedDescription)"
                 await MainActor.run {
                     if let index = messages.firstIndex(where: { $0.id == botResponsePlaceholderId }) {
                         messages[index].text = errorText // Update placeholder with error
                     } else {
                         messages.append(Message(text: errorText, isUser: false))
                     }
                 }
                 shouldContinueLoop = false
            }

            // --- Assemble Final Tool Calls (if any) ---
            var assembledToolCalls: [AssembledToolCall] = []
            // Assume normal completion unless we explicitly got "tool_calls"
            var treatAsNormalCompletion = true 
            
            if finalFinishReason == "tool_calls" {
                shouldContinueLoop = true // Signal to execute tools and loop back
                treatAsNormalCompletion = false // It's not a normal completion, it's a tool call request
                for (index, partialCall) in toolCallAccumulator.sorted(by: { $0.key < $1.key }) { // Ensure order
                    guard let id = partialCall.id, let name = partialCall.name else {
                         print("Warning: Incomplete tool call data at index \(index): ID or Name missing.")
                         continue
                    }
                    assembledToolCalls.append(AssembledToolCall(index: index, id: id, functionName: name, arguments: partialCall.arguments))
                }
                print("Assembled \(assembledToolCalls.count) tool calls from stream.")
            } else if Task.isCancelled {
                 // If cancelled, don't treat as normal completion, let UI state handle itself
                 treatAsNormalCompletion = false
                 shouldContinueLoop = false 
            }
            // If finalFinishReason is nil and not cancelled, treatAsNormalCompletion remains true
            // and shouldContinueLoop will become false in the next step.

            // Update shouldContinueLoop based on the final decision
            if treatAsNormalCompletion {
                shouldContinueLoop = false
            }

            // --- Process Results - Update UI and History Based on Completion Type ---
            await MainActor.run {
                let placeholderIndex = messages.firstIndex(where: { $0.id == botResponsePlaceholderId })

                if !treatAsNormalCompletion && !assembledToolCalls.isEmpty { // Tool Calls Path
                    print("Proceeding with tool call execution (\(assembledToolCalls.count) calls).")
                    // Replace placeholder content with "[Processing Tools...]" message
                    if let index = placeholderIndex {
                        messages[index].text = "[Processing Tools...]" // Update existing message
                    } else {
                        print("Error: Could not find placeholder message ID \(botResponsePlaceholderId) to update for tool status.")
                        messages.append(Message(text: "[Processing Tools...]", isUser: false))
                    }
                    // Add assistant message with tool calls to history
                    let toolCallDictsForHistory: [[String: Any]] = assembledToolCalls.map { tc in
                        ["id": tc.id, "type": "function", "function": ["name": tc.functionName, "arguments": tc.arguments]]
                    }
                    messageHistory.append(["role": "assistant", "tool_calls": toolCallDictsForHistory, "content": NSNull()])
                    print("Assistant message with tool_calls added to history.")

                } else if treatAsNormalCompletion, let index = placeholderIndex { // Normal Completion Path (Stop or nil finishReason)
                    print("Stream finished normally or without explicit stop signal. Finalizing response in UI.")
                    let finalContent = messages[index].text // Get the fully streamed content
                    if finalContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                         print("Final streamed content is empty, removing placeholder message.")
                         messages.remove(at: index)
                    } else {
                        messageHistory.append(["role": "assistant", "content": finalContent])
                        print("Final assistant text message added to history.")
                    }
                } else if placeholderIndex == nil && !Task.isCancelled {
                     // Log warning only if not cancelled and placeholder is missing
                     print("Warning: Placeholder message not found after stream completion.")
                }
                // If cancelled, no final UI/History update needed here
            } // End MainActor.run

            // --- Execute Tools (if needed, outside MainActor block) ---
            // This check now correctly uses shouldContinueLoop which was determined above
             if shouldContinueLoop && !assembledToolCalls.isEmpty {
                 var toolResultsForHistory: [[String: Any]] = []
                 for toolCall in assembledToolCalls {
                     let result = await executeToolCall(toolCall)
                     toolResultsForHistory.append(["role": "tool", "tool_call_id": toolCall.id, "content": result.content])
                 }
                 // Append tool results to history *after* execution
                 await MainActor.run { // Modify history on main thread
                    messageHistory.append(contentsOf: toolResultsForHistory)
                 }
                 print("Tool results added. Looping back.")
             }
             // No 'else' needed, shouldContinueLoop dictates the next iteration

        } // End while loop
        print("--- Interaction Loop Finished ---")
        await MainActor.run { isSending = false } // Ensure state change is on main thread
    }

    // --- Tool Execution (accepts AssembledToolCall) ---
    struct ToolResult { let content: String }

    private func executeToolCall(_ toolCall: AssembledToolCall) async -> ToolResult {
        let functionName = toolCall.functionName
        let argumentsString = toolCall.arguments
        var resultJsonString = "{\"error\": \"Tool execution failed\"}"
        print("Executing Tool: \(functionName) args: \(argumentsString)")

        guard let argsData = argumentsString.data(using: .utf8) else {
            return ToolResult(content: "{\"error\": \"Invalid argument encoding\"}")
        }
        let decoder = JSONDecoder()
        do {
            var functionResponseDict: [String: Any?] = [:]
            switch functionName {
            case "find_order_by_name":
                let decodedArgs = try decoder.decode(ToolCallArgsFindOrder.self, from: argsData)
                functionResponseDict = self.findOrderByName(customerName: decodedArgs.customer_name)
            case "get_delivery_date":
                let decodedArgs = try decoder.decode(ToolCallArgsGetDelivery.self, from: argsData)
                functionResponseDict = self.getDeliveryDate(orderId: decodedArgs.order_id)
            default:
                functionResponseDict = ["error": "Unknown function: \(functionName)"]
            }
            let resultData = try JSONSerialization.data(withJSONObject: functionResponseDict.mapValues { $0 ?? NSNull() }, options: [])
            resultJsonString = String(data: resultData, encoding: .utf8) ?? "{\"error\": \"Failed to encode tool result\"}"
        } catch {
            resultJsonString = "{\"error\": \"Tool execution error: \(error.localizedDescription)\"}"
        }
        print("Execution Result: \(resultJsonString)")
        return ToolResult(content: resultJsonString)
    }

    // Mock Tool Implementations
    func findOrderByName(customerName: String) -> [String: Any?] {
        print("--- Swift Tool Call: findOrderByName(customerName: '\(customerName)') ---")
        let trimmedName = customerName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.contains(" ") && trimmedName.count > 3 {
            let simulatedId = "ORD-\(trimmedName.split(separator: " ").first?.prefix(3).uppercased() ?? "UNK")\(String(format: "%02d", trimmedName.count))"
            print("  -> Found order ID: \(simulatedId)")
            return ["order_id": simulatedId]
        } else {
            print("  -> No order found for name: '\(customerName)'")
            return ["order_id": nil, "message": "Could not find order for '\(customerName)'. Verify name."]
        }
    }

    func getDeliveryDate(orderId: String) -> [String: Any?] {
        print("--- Swift Tool Call: getDeliveryDate(orderId: '\(orderId)') ---")
        let trimmedId = orderId.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedId.starts(with: "ORD-") {
            let estimatedDelivery = Calendar.current.date(byAdding: .day, value: 3, to: Date())!
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            dateFormatter.timeZone = TimeZone(secondsFromGMT: 0) // Use UTC for consistency
            let dateString = dateFormatter.string(from: estimatedDelivery)
            print("  -> Estimated Delivery: \(dateString)")
            return ["order_id": orderId, "estimated_delivery_date": dateString]
        } else {
            print("  -> Invalid Order ID format: '\(orderId)'")
            return ["error": "Invalid order_id format: '\(orderId)'."]
        }
    }
}

struct ContentView: View {
    // State for search text
    @State private var searchText = ""
    // State to manage chat history filtering (if implementing search)
    // @State private var filteredChatHistory = mockChatHistory
    @State private var contentVisible = false // State for fade-in - RESTORED
    @Environment(\.colorScheme) var colorScheme // Detect light/dark mode

    var body: some View {
        ZStack { // Wrap in ZStack for fade-in from black - RESTORED
            // Background adapts to color scheme
            (colorScheme == .dark ? Color.black : Color(NSColor.windowBackgroundColor))
                .edgesIgnoringSafeArea(.all)

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
            .toolbar { // Add toolbar for the toggle button
                ToolbarItem(placement: .navigation) { // Place it near the trailing edge/primary actions
                    Button(action: toggleSidebar) {
                        Label("Toggle Sidebar", systemImage: "sidebar.left")
                    }
                }
            }
            .frame(minWidth: 600, minHeight: 400)
            // Apply fade-in effect to the NavigationView - RESTORED
            .opacity(contentVisible ? 1 : 0)
            .background( // Set the actual background color of the content area - RESTORED
                 Color(NSColor.windowBackgroundColor)
            )
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
}

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

// Separate View for Message Bubble Styling
struct MessageView: View {
    @ObservedObject var message: Message
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack {
            if message.isUser {
                Spacer() // Push user messages to the right
            }

            VStack(alignment: message.isUser ? .trailing : .leading) {
                 Text(message.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    // Use new color scheme for messages, adapting to light/dark mode
                    .background(message.isUser ? Color.nuevoOrange : (colorScheme == .dark ? Color.nuevoDarkGray : Color(white: 0.9)))
                    .foregroundColor(message.isUser ? .white : (colorScheme == .dark ? .nuevoLightGray : .primary))
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

// Helper function to call the standard toggleSidebar action (macOS)
private func toggleSidebar() {
    #if os(macOS)
    NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
    #endif
}

#Preview {
    // Preview the main ContentView which now includes the sidebar
    ContentView()
        // Remove preferred color scheme to see both light and dark previews
}
