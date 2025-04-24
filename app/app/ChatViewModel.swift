import SwiftUI
import Combine
import Foundation // For URLSession, JSONEncoder/Decoder, Date etc.

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
    You are a helpful assistant. Answer the user's questions directly and concisely.

    You have the following tools available:
    - `find_order_by_name`: Looks up an order ID based on the customer's full name. Use this *only* when the user asks about their specific order and provides a name.
    - `get_delivery_date`: Gets the estimated delivery date for a given `order_id`. Use this *only* after `find_order_by_name` successfully returns an `order_id`.

    Follow these guidelines:
    1. If the user asks a general question, answer it directly without using tools.
    2. If the user asks about their order/delivery without providing a name, ask for their *full name*.
    3. If the user provides a name when asking about their order, use `find_order_by_name`.
    4. If `find_order_by_name` finds an `order_id`, use `get_delivery_date` with that ID.
    5. If `find_order_by_name` fails or doesn't find an order, inform the user politely.
    6. If a tool call results in an error, inform the user.
    Be helpful and conversational.
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
            // Assume normal completion unless we explicitly got "tool_calls" or parsed them client-side
            var treatAsNormalCompletion = true 

            if finalFinishReason == "tool_calls" {
                print("[Tool Call Source]: Stream finish_reason")
                shouldContinueLoop = true // Signal to execute tools and loop back
                treatAsNormalCompletion = false // It's not a normal completion, it's a tool call request
                for (index, partialCall) in toolCallAccumulator.sorted(by: { $0.key < $1.key }) { // Ensure order
                    guard let id = partialCall.id, let name = partialCall.name else {
                         print("Warning: Incomplete tool call data at index \(index): ID or Name missing.")
                         continue
                    }
                    assembledToolCalls.append(AssembledToolCall(index: index, id: id, functionName: name, arguments: partialCall.arguments))
                }
                print("Assembled \(assembledToolCalls.count) tool calls from stream finish_reason.")
            
            // --- BEGIN Client-Side Parsing Fallback ---
            } else if !Task.isCancelled { 
                // Check text content if finish_reason wasn't tool_calls
                // Need to get the final text content first on the MainActor
                var finalContentFromPlaceholder: String? = nil
                await MainActor.run {
                    if let index = messages.firstIndex(where: { $0.id == botResponsePlaceholderId }) {
                        finalContentFromPlaceholder = messages[index].text
                    }
                }

                if let textToCheck = finalContentFromPlaceholder, !textToCheck.isEmpty {
                     let parsedCalls = parseToolCallsFrom(text: textToCheck) // Call the new helper
                     if !parsedCalls.isEmpty {
                         print("[Tool Call Source]: Client-side parsing fallback")
                         assembledToolCalls = parsedCalls
                         shouldContinueLoop = true
                         treatAsNormalCompletion = false
                         print("Assembled \(assembledToolCalls.count) tool calls via client-side parsing.")
                         // Clear the placeholder text as it contained only tool calls
                         await MainActor.run {
                              if let index = messages.firstIndex(where: { $0.id == botResponsePlaceholderId }) {
                                   messages[index].text = "" 
                              }
                         }
                     }
                }
            // --- END Client-Side Parsing Fallback ---

            } else if Task.isCancelled { // Handle cancellation explicitly
                 treatAsNormalCompletion = false
                 shouldContinueLoop = false 
            }
            
            // If neither finish_reason nor parsing yielded tools, it's a normal completion
            if treatAsNormalCompletion {
                shouldContinueLoop = false
            }

            // --- Process Results - Update UI and History Based on Completion Type ---
            // This block now correctly handles tool calls identified either way
            await MainActor.run {
                let placeholderIndex = messages.firstIndex(where: { $0.id == botResponsePlaceholderId })

                if !treatAsNormalCompletion && !assembledToolCalls.isEmpty { // Tool Calls Path (Stream OR Client-Parsed)
                    print("Proceeding with tool call execution (\(assembledToolCalls.count) calls).")
                    // Update placeholder content to "[Processing Tools...]" 
                    // This is safe even if we cleared it earlier during client parsing
                    if let index = placeholderIndex {
                        messages[index].text = "[Processing Tools...]" 
                    } else {
                        print("Error: Could not find placeholder message ID \(botResponsePlaceholderId) to update for tool status.")
                        // Avoid adding duplicate processing message if placeholder gone
                        // messages.append(Message(text: "[Processing Tools...]", isUser: false)) 
                    }
                    
                    // Add assistant message with tool calls to history
                    let toolCallDictsForHistory: [[String: Any]] = assembledToolCalls.map { tc in
                        ["id": tc.id, "type": "function", "function": ["name": tc.functionName, "arguments": tc.arguments]]
                    }
                    // Use NSNull() for null content when tool calls are present
                    messageHistory.append(["role": "assistant", "tool_calls": toolCallDictsForHistory, "content": NSNull()]) 
                    print("Assistant message with tool_calls added to history.")

                } else if treatAsNormalCompletion, let index = placeholderIndex { // Normal Completion Path (No tool calls identified)
                    print("Stream finished without tool calls. Finalizing response in UI.")
                    let finalContent = messages[index].text // Get the potentially streamed content
                    if finalContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                         print("Final streamed content is empty or was cleared for client-parsed tools, removing placeholder message.")
                         // Ensure removal happens only if the index is still valid
                         if messages.indices.contains(index) {
                              messages.remove(at: index)
                         }
                    } else {
                        // Only add to history if there's actual content
                        messageHistory.append(["role": "assistant", "content": finalContent])
                        print("Final assistant text message added to history.")
                    }
                } else if placeholderIndex == nil && !Task.isCancelled {
                     // Log warning only if not cancelled and placeholder is missing
                     print("Warning: Placeholder message not found after stream completion and processing.")
                }
                 // If cancelled, no final UI/History update needed here
            } // End MainActor.run

            // --- Execute Tools (if needed, outside MainActor block) ---
            // This check now correctly uses shouldContinueLoop which was determined above
             if shouldContinueLoop && !assembledToolCalls.isEmpty {
                 var toolResultsForHistory: [[String: Any]] = []
                 for toolCall in assembledToolCalls {
                     let result = await executeToolCall(toolCall)
                     // Format for history: API expects tool_call_id and content (as string)
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

    // --- Helper Function for Client-Side Tool Call Parsing ---
    private func parseToolCallsFrom(text: String) -> [AssembledToolCall] {
        var parsedCalls: [AssembledToolCall] = []
        // Regex to find <tool_call>{...}</tool_call> blocks
        // Using NSRegularExpression for robust pattern matching
        let pattern = "<tool_call>(.*?)</tool_call>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            print("Error creating tool call regex.")
            return []
        }

        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: nsRange)

        print("--- Attempting Client-Side Parse on text: ---")
        print(text)
        print("--- Found \(matches.count) potential matches ---")

        for (matchIndex, match) in matches.enumerated() {
            // Ensure we capture the group inside the tags (index 1)
            guard match.numberOfRanges >= 2, 
                  let range = Range(match.range(at: 1), in: text) else { continue }
            
            let jsonString = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            print("  Match \(matchIndex): Extracted JSON String: \(jsonString)")

            guard let jsonData = jsonString.data(using: .utf8) else {
                 print("  Match \(matchIndex): Error converting JSON string to data.")
                 continue 
            }

            do {
                // Try decoding into a flexible structure first
                if let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] {
                    // --- Expecting structure like: {"name": "func_name", "arguments": "{...}"} ---
                    // --- Or sometimes: {"function": {"name": "func_name", "arguments": "{...}"}} ---
                    // --- Or even just: {"name": "func_name", "arguments": {...}} ---
                    
                    var funcName: String?
                    var funcArgsString: String?

                    if let name = jsonObject["name"] as? String { // Direct name/arguments
                        funcName = name
                        if let argsDict = jsonObject["arguments"] as? [String: Any] {
                             // Re-encode dictionary arguments to string
                             if let argsData = try? JSONSerialization.data(withJSONObject: argsDict, options: []),
                                let argsStr = String(data: argsData, encoding: .utf8) {
                                 funcArgsString = argsStr
                             } else {
                                  print("  Match \(matchIndex): Failed to re-encode dictionary arguments.")
                                  funcArgsString = "{}" // Default to empty JSON object string on failure
                             }
                        } else if let argsStr = jsonObject["arguments"] as? String {
                            funcArgsString = argsStr // Arguments already a string
                        }
                    } else if let funcDict = jsonObject["function"] as? [String: Any], // Nested under "function"
                              let name = funcDict["name"] as? String {
                         funcName = name
                         if let argsDict = funcDict["arguments"] as? [String: Any] {
                              if let argsData = try? JSONSerialization.data(withJSONObject: argsDict, options: []),
                                 let argsStr = String(data: argsData, encoding: .utf8) {
                                  funcArgsString = argsStr
                              } else {
                                   print("  Match \(matchIndex): Failed to re-encode dictionary arguments (nested).")
                                   funcArgsString = "{}"
                              }
                         } else if let argsStr = funcDict["arguments"] as? String {
                              funcArgsString = argsStr
                         }
                    }

                    if let name = funcName, let args = funcArgsString {
                        let toolCallId = "call_\(UUID().uuidString.prefix(12))_parsed_\(matchIndex)"
                        let assembledCall = AssembledToolCall(index: matchIndex, // Use match index for ordering
                                                              id: toolCallId,
                                                              functionName: name,
                                                              arguments: args)
                        parsedCalls.append(assembledCall)
                        print("  Match \(matchIndex): Successfully Parsed: ID=\(toolCallId), Name=\(name), Args=\(args)")
                    } else {
                         print("  Match \(matchIndex): Failed to extract name or arguments from JSON: \(jsonObject)")
                    }
                } else {
                    print("  Match \(matchIndex): Decoded JSON is not a dictionary.")
                }
            } catch {
                print("  Match \(matchIndex): JSON Decoding Error: \(error.localizedDescription)")
            }
        }
        print("--- Client-Side Parse Finished. Found \(parsedCalls.count) valid calls. ---")
        return parsedCalls
    }

    // --- Tool Execution (accepts AssembledToolCall) ---
    struct ToolResult { let content: String } // Keep content as String (JSON)

    private func executeToolCall(_ toolCall: AssembledToolCall) async -> ToolResult {
        let functionName = toolCall.functionName
        let argumentsString = toolCall.arguments
        var resultJsonString = "{\"error\": \"Tool execution failed\"}" // Default error JSON
        print("Executing Tool: \(functionName) args: \(argumentsString)")

        guard let argsData = argumentsString.data(using: .utf8) else {
            return ToolResult(content: "{\"error\": \"Invalid argument encoding\"}")
        }
        let decoder = JSONDecoder()
        do {
            var functionResponseDict: [String: Any?] = [:] // Use Any? for potential nil from tools
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
            // Convert the [String: Any?] result back to JSON Data, handling potential nil values
            let resultData = try JSONSerialization.data(withJSONObject: functionResponseDict.mapValues { $0 ?? NSNull() }, options: [])
            resultJsonString = String(data: resultData, encoding: .utf8) ?? "{\"error\": \"Failed to encode tool result\"}"
        } catch let decodingError as DecodingError {
             resultJsonString = "{\"error\": \"Tool argument decoding error: \(decodingError.localizedDescription). Argument string: \(argumentsString)\"}"
             print("Decoding Error: \(decodingError) for args: \(argumentsString)")
        } catch {
            resultJsonString = "{\"error\": \"Tool execution/encoding error: \(error.localizedDescription)\"}"
            print("Tool Execution/Encoding Error: \(error)")
        }
        print("Execution Result (JSON String): \(resultJsonString)")
        return ToolResult(content: resultJsonString)
    }

    // Mock Tool Implementations
    func findOrderByName(customerName: String) -> [String: Any?] {
        print("--- Swift Tool Call: findOrderByName(customerName: '\(customerName)') ---")
        let trimmedName = customerName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.contains(" ") && trimmedName.count > 3 {
            let simulatedId = "ORD-\(trimmedName.split(separator: " ").first?.prefix(3).uppercased() ?? "UNK")\(String(format: "%02d", trimmedName.count))"
            print("  -> Found order ID: \(simulatedId)")
            return ["order_id": simulatedId] // Return non-optional String
        } else {
            print("  -> No order found for name: '\(customerName)'")
            // Return nil for order_id as per API spec for 'not found'
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