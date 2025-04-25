import SwiftUI
import Combine
import Foundation // For URLSession, JSONEncoder/Decoder, Date etc.

// --- Placeholder for Brave Search API Key ---
// IMPORTANT: Replace with your actual key and load securely (e.g., from Settings/Environment)
private let braveSearchAPIKey = "YOUR_BRAVE_API_KEY_HERE"

// --- Helper Structs for API Responses ---

// Basic structure for Brave Search API web results
struct BraveSearchResponse: Decodable {
    let web: BraveWebResults?
}

struct BraveWebResults: Decodable {
    let results: [BraveSearchResult]?
}

struct BraveSearchResult: Decodable {
    let title: String?
    let url: String?
    let description: String?
    // Add other fields if needed
}

// Simplified structure for non-streaming Chat Completion response (for summarization)
struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let role: String?
            let content: String?
        }
        let message: Message?
        let finish_reason: String?
    }
    let choices: [Choice]?
    // Add other fields like 'usage' if needed
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
You are cupertino.ink, an AI assistant designed to run locally on the user's machine.

The current date is {{currentDateTime}}.

You operate **offline** and have **no access to the internet or real-time information**. Your knowledge is limited to the data you were trained on. You cannot browse websites, access external databases, or retrieve current events.

**Core Functionality:**
*   Assist the user with tasks like analysis, question answering, math, coding, creative writing, teaching, and general discussion, based **only** on the information provided in the conversation and your internal training data.
*   When presented with problems requiring systematic thinking (math, logic), think step-by-step before providing an answer.
*   Use Markdown for formatting, especially for code blocks. Follow standard Markdown best practices (e.g., spacing for headers, consistent list formatting).

**Interaction Style:**
*   Be helpful, accurate (within your knowledge limits), and efficient.
*   Provide concise responses to simple questions and more thorough answers to complex ones.
*   If a task is ambiguous, ask clarifying questions. Only ask the single most relevant follow-up question when necessary.
*   Vary your language naturally, avoiding repetitive phrases or rote statements.
*   Respond in the language the user uses or requests.
*   Do not use unnecessary caveats like "I aim to be direct...". Respond straightforwardly.

**Handling Limitations:**
*   If asked about events or information beyond your training data or requiring internet access, clearly state your limitations (local operation, no real-time data) and explain why you cannot provide the information.
*   If asked to access URLs, links, or external files, explain that you cannot perform these actions and ask the user to provide the relevant content directly.
*   If asked about very obscure topics, state that the information is likely outside your training data rather than attempting to guess or hallucinate. Acknowledge the limits of your knowledge base.
*   Since you cannot access external sources, do not pretend to cite articles, papers, or books. Explain that any apparent citations would be fabricated.

**Sensitive & Harmful Content:**
*   Provide factual information based on your training data about potentially sensitive or risky topics if requested for educational purposes, but do not promote harmful activities. If discussing risks, clearly state them.
*   If a user query has both a potentially harmful and a harmless interpretation, assume the harmless one. If unsure, ask for clarification.
*   Decline requests for assistance with harmful, illegal, unethical, or dangerous activities. Explain politely that you cannot fulfill the request due to safety guidelines or your operational constraints.

**Persona:**
*   Maintain a helpful and professional assistant persona.
*   If asked innocuous questions about preferences or experiences, you can respond hypothetically without needing to over-emphasize your AI nature, but keep it brief and relevant.

You are now being connected with a human.
"""

    // Corrected History Type: Use [String: Any] to allow complex values like tool_calls
    private var messageHistory: [[String: Any]] = []

    init() {
        // 1. Get current date and time
        let now = Date()
        // 2. Format it (e.g., "yyyy-MM-dd HH:mm:ss Z")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZ" // Using ISO 8601-like format
        formatter.timeZone = TimeZone.current // Use local timezone for display in prompt
        let dateTimeString = formatter.string(from: now)

        // 3. Replace the placeholder in the system prompt template
        let processedSystemPrompt = systemPrompt.replacingOccurrences(of: "{{currentDateTime}}", with: dateTimeString)

        // 4. Initialize history with the processed prompt
        messageHistory.append(["role": "system", "content": processedSystemPrompt])
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
        jsonEncoder.outputFormatting = .prettyPrinted // Optional: for debugging encoded JSON
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
                model: modelName, // Assuming modelName is accessible (moved to Utilities)
                messages: messagesForRequest,
                tools: availableToolsDict, // Assuming availableToolsDict is accessible (moved to Models/ToolRegistry later)
                tool_choice: "auto",
                stream: true
            )
            guard let url = URL(string: baseURL) else { // Assuming baseURL is accessible (moved to Utilities)
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
            var treatAsNormalCompletion = true // Assume normal completion unless tools are called

            if finalFinishReason == "tool_calls" || !toolCallAccumulator.isEmpty { // Also handle if accumulator has data even without explicit finish_reason
                print("[Tool Call Source]: Stream finish_reason ('\(finalFinishReason ?? "N/A")') or accumulator has data.")
                treatAsNormalCompletion = false // It's not a normal completion if tools were involved

                for (index, partialCall) in toolCallAccumulator.sorted(by: { $0.key < $1.key }) { // Ensure order
                    guard let id = partialCall.id, let name = partialCall.name else {
                         print("Warning: Incomplete tool call data at index \(index): ID ('\(partialCall.id ?? "nil")') or Name ('\(partialCall.name ?? "nil")') missing. Arguments: '\(partialCall.arguments)'")
                         continue // Skip incomplete tool calls
                    }
                    assembledToolCalls.append(AssembledToolCall(index: index, id: id, functionName: name, arguments: partialCall.arguments))
                }

                // NEW: Add the assistant message with tool calls to history *before* handling them
                let assistantMessageWithToolCalls: [String: Any] = [
                    "role": "assistant",
                    "content": NSNull(), // Use NSNull for nil content when there are tool calls
                    "tool_calls": assembledToolCalls.map { call in // Map AssembledToolCall back to API format
                        [
                            "id": call.id,
                            "type": "function",
                            "function": [
                                "name": call.functionName,
                                "arguments": call.arguments // Arguments are already a JSON string
                            ]
                        ]
                    }
                ]
                messageHistory.append(assistantMessageWithToolCalls)

                // --- Handle Assembled Tool Calls ---
                if !assembledToolCalls.isEmpty {
                    print("Handling \(assembledToolCalls.count) assembled tool call(s)...")
                    await handleToolCalls(assembledToolCalls) // Call the new handler function
                    shouldContinueLoop = true // Signal to loop back and call the LLM again with tool results
                } else {
                     print("No valid tool calls assembled despite finish_reason/accumulator data.")
                     shouldContinueLoop = false // Don't loop if no tools were actually executed
                }

            } else {
                // --- Handle Normal Completion (No Tool Calls) ---
                print("Processing as normal completion (no tool calls detected).")
                treatAsNormalCompletion = true
                shouldContinueLoop = false // End the loop after a normal response
            }

            // --- Finalize Assistant Message in UI and History ---
            if treatAsNormalCompletion {
                await MainActor.run {
                    if let index = messages.firstIndex(where: { $0.id == botResponsePlaceholderId }) {
                        let finalMessageContent = messages[index].text
                         print("Finalizing normal assistant message in history: \(finalMessageContent)")
                        // Only add non-empty final message to history
                        if !finalMessageContent.isEmpty {
                             messageHistory.append(["role": "assistant", "content": finalMessageContent])
                        } else if messages.count > 1 && messages[messages.count - 2].isUser {
                             // Handle cases where the stream might end without content (e.g., error or empty response)
                             // Avoid adding an empty assistant message if the last one was user's
                             print("Warning: Empty assistant message content after normal completion.")
                             // Optionally remove the empty placeholder from UI if desired
                             // messages.remove(at: index)
                        }
                    } else {
                         print("Error: Could not find placeholder message ID \(botResponsePlaceholderId) to finalize history.")
                    }
                }
            }

            // Add logging for history after API call/tool handling
            print("--- History After API Call/Tools (Turn End) ---")
            do {
                 let historyData = try JSONSerialization.data(withJSONObject: messageHistory, options: .prettyPrinted)
                 print(String(data: historyData, encoding: .utf8) ?? "Failed to print history")
            } catch { print("Error printing history: \(error)") }
            print("-------------------------------------------")

            // Reset task state only if the loop isn't continuing due to tool calls
            if !shouldContinueLoop {
                 isSending = false
                 currentTask = nil
            }
            
            print("End of processChatInteraction loop. Continue = \(shouldContinueLoop)")

        } // End while loop

         // Ensure sending state is reset if the loop terminates unexpectedly or task is cancelled
         if Task.isCancelled {
             print("Task cancelled, resetting sending state.")
             isSending = false
         }
         // Final check to ensure isSending is false if loop finishes
         if !shouldContinueLoop {
             isSending = false
         }
    }

    // NEW: Function to handle tool execution
    private func handleToolCalls(_ calls: [AssembledToolCall]) async {
        let jsonDecoder = JSONDecoder()

        for call in calls {
            var toolResultContent: String = "" // Content to send back to the model

            print("Executing Tool: \(call.functionName), ID: \(call.id)")
            do {
                guard let argumentsData = call.arguments.data(using: .utf8) else {
                    throw NSError(domain: "ToolError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode arguments to Data"])
                }

                switch call.functionName {
                case "find_order_by_name":
                    let args = try jsonDecoder.decode(ToolCallArgsFindOrder.self, from: argumentsData)
                    // --- Placeholder: Implement actual find_order_by_name logic ---
                    print("  Args: customer_name=\(args.customer_name)")
                    // Replace with actual logic (e.g., database lookup)
                    let mockOrderId = "ORDER-\(String(abs(args.customer_name.hashValue)).prefix(6))"
                    toolResultContent = "{\"order_id\": \"\(mockOrderId)\"}"
                    // --- End Placeholder ---

                case "get_delivery_date":
                    let args = try jsonDecoder.decode(ToolCallArgsGetDelivery.self, from: argumentsData)
                    // --- Placeholder: Implement actual get_delivery_date logic ---
                    print("  Args: order_id=\(args.order_id)")
                    // Replace with actual logic (e.g., API call, database lookup)
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    let deliveryDate = Calendar.current.date(byAdding: .day, value: 3, to: Date())!
                    toolResultContent = "{\"estimated_delivery_date\": \"\(formatter.string(from: deliveryDate))\"}"
                    // --- End Placeholder ---

                case "brave_search":
                    // --- Implement Brave Search ---
                     print("Decoding Brave Search Args...")
                    let args = try jsonDecoder.decode(ToolCallArgsBraveSearch.self, from: argumentsData)
                     print("  Args: query=\(args.query)")

                    guard !braveSearchAPIKey.isEmpty && braveSearchAPIKey != "YOUR_BRAVE_API_KEY_HERE" else {
                        print("Error: Brave Search API Key not configured.")
                        toolResultContent = "{\"error\": \"Brave Search API Key not configured.\"}"
                        break // Break from switch case for this tool
                    }

                    guard var urlComponents = URLComponents(string: "https://api.search.brave.com/res/v1/web/search") else {
                        print("Error: Invalid Brave Search API base URL.")
                        toolResultContent = "{\"error\": \"Internal configuration error (invalid URL).\"}"
                        break
                    }
                    urlComponents.queryItems = [URLQueryItem(name: "q", value: args.query)]
                    // Add other params like count, safesearch if needed

                    guard let url = urlComponents.url else {
                        print("Error: Could not create Brave Search URL with query items.")
                        toolResultContent = "{\"error\": \"Internal configuration error (URL creation failed).\"}"
                        break
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "GET" // Brave Search uses GET
                    request.setValue("application/json", forHTTPHeaderField: "Accept")
                    request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
                    request.setValue(braveSearchAPIKey, forHTTPHeaderField: "X-Subscription-Token")

                    print("  Making Brave Search API Call...")
                    do {
                        let (data, response) = try await URLSession.shared.data(for: request)
                        guard let httpResponse = response as? HTTPURLResponse else {
                             throw NSError(domain: "NetworkError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid response type"])
                        }
                        
                        print("  Brave Search Response Status Code: \(httpResponse.statusCode)")

                        if (200...299).contains(httpResponse.statusCode) {
                             let searchResponse = try jsonDecoder.decode(BraveSearchResponse.self, from: data)
                             print("  Brave Search Response Decoded.")
                            // Format results concisely
                            var resultsString = "Search Results for '\(args.query)':\n"
                            if let webResults = searchResponse.web?.results, !webResults.isEmpty {
                                for (index, result) in webResults.prefix(5).enumerated() { // Limit to top 5 results
                                     resultsString += "\n\(index + 1). \(result.title ?? "No Title")"
                                     resultsString += "\n   URL: \(result.url ?? "No URL")"
                                     resultsString += "\n   Snippet: \(result.description ?? "No Snippet")\n"
                                }
                            } else {
                                 resultsString += "\nNo results found."
                            }
                             toolResultContent = try String(data: JSONEncoder().encode(["results": resultsString]), encoding: .utf8) ?? "{\"error\": \"Failed to encode search results string\"}";
                        } else {
                             let errorBody = String(data: data, encoding: .utf8) ?? "Could not decode error body"
                             print("  Brave Search API Error (Status \(httpResponse.statusCode)): \(errorBody)")
                            toolResultContent = "{\"error\": \"Brave Search API failed with status \(httpResponse.statusCode). Details: \(errorBody)\"}"
                        }
                    } catch {
                         print("  Brave Search URLSession/Decoding Error: \(error)")
                        toolResultContent = "{\"error\": \"Failed to execute Brave Search: \(error.localizedDescription)\"}"
                    }
                    // --- End Brave Search ---

                case "summarize_content":
                    // --- Implement Summarization ---
                     print("Decoding Summarize Args...")
                    let args = try jsonDecoder.decode(ToolCallArgsSummarizeContent.self, from: argumentsData)
                     print("  Args: content_to_summarize length=\(args.content_to_summarize.count)")
                    
                    let summarizationPrompt = "Please summarize the following content concisely:\n\n---\n\n\(args.content_to_summarize)\n\n---\n\nSummary:"

                    // Prepare request for the *same* LLM API
                    let summarizationMessages: [[String: AnyEncodable]] = [
                        ["role": AnyEncodable("system"), "content": AnyEncodable("You are a helpful summarization assistant.")],
                        ["role": AnyEncodable("user"), "content": AnyEncodable(summarizationPrompt)]
                    ]
                    let summarizationRequestBody = ChatCompletionRequestBody(
                        model: modelName,
                        messages: summarizationMessages,
                        tools: nil, // No tools for summarization call
                        tool_choice: nil, // No tool choice
                        stream: false // Request non-streaming response for simplicity
                    )

                    guard let url = URL(string: baseURL) else {
                        print("Error: Invalid API URL for summarization.")
                        toolResultContent = "{\"error\": \"Internal configuration error (invalid URL for summarization).\"}"
                        break
                    }
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("application/json", forHTTPHeaderField: "Accept") // Expect JSON back

                    do {
                         request.httpBody = try JSONEncoder().encode(summarizationRequestBody)
                         print("  Making Summarization API Call...")
                         let (data, response) = try await URLSession.shared.data(for: request)
                         guard let httpResponse = response as? HTTPURLResponse else {
                             throw NSError(domain: "NetworkError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid response type"])
                        }
                         
                         print("  Summarization Response Status Code: \(httpResponse.statusCode)")

                         if (200...299).contains(httpResponse.statusCode) {
                             let summaryResponse = try jsonDecoder.decode(ChatCompletionResponse.self, from: data)
                             if let summary = summaryResponse.choices?.first?.message?.content {
                                 print("  Summarization Response Decoded. Summary length: \(summary.count)")
                                 toolResultContent = try String(data: JSONEncoder().encode(["summary": summary]), encoding: .utf8) ?? "{\"error\": \"Failed to encode summary string\"}"
                             } else {
                                 print("  Error: Could not extract summary content from LLM response.")
                                 toolResultContent = "{\"error\": \"Failed to get summary from the model response.\"}"
                             }
                              } else {
                             let errorBody = String(data: data, encoding: .utf8) ?? "Could not decode error body"
                             print("  Summarization API Error (Status \(httpResponse.statusCode)): \(errorBody)")
                             toolResultContent = "{\"error\": \"Summarization API failed with status \(httpResponse.statusCode). Details: \(errorBody)\"}"
                         }
                    } catch {
                         print("  Summarization URLSession/Encoding/Decoding Error: \(error)")
                         toolResultContent = "{\"error\": \"Failed to execute summarization: \(error.localizedDescription)\"}"
                    }
                    // --- End Summarization ---

                default:
                    print("  Warning: Unknown tool function name '\(call.functionName)'")
                    toolResultContent = "{\"error\": \"Unknown tool function name encountered.\"}"
                }

            } catch {
                print("Error decoding arguments or processing tool \(call.functionName): \(error)")
                toolResultContent = "{\"error\": \"Failed to decode arguments for tool \(call.functionName): \(error.localizedDescription)\"}"
            }

            // --- Append Tool Result to History ---
            // Ensure content is valid JSON string before adding (it should be by now)
            let toolMessage: [String: Any] = [
                "role": "tool",
                "tool_call_id": call.id,
                "content": toolResultContent // This should be a JSON string representing the result
            ]
            messageHistory.append(toolMessage)
            print("Appended result for Tool ID \(call.id) to history.")
        }
    }

    func cancelStreaming() {
        // ... existing code ...
    } // End Class
} 
