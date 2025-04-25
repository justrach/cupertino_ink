import SwiftUI
import Combine
import Foundation // For URLSession, JSONEncoder/Decoder, Date etc.
import MCP // Import MCP SDK
import os.log // Use os.log

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
    // --- EnvironmentObject for MCP ---
    @EnvironmentObject var mcpHost: MCPHost // Access the MCPHost instance

    @Published var messages: [Message] = [
        // Initial message or load from history
        Message(text: "Hello! How can I help you today?", isUser: false)
    ]
    @Published var newMessageText: String = ""
    @Published var isSending: Bool = false // To disable input while processing
    @Published var errorMessage: String? = nil // To display errors to the user

    private var currentTask: Task<Void, Never>? = nil
    // Access logger from MCPHost or create a specific one
    private let logger = Logger(subsystem: "com.cupertino_ink.chat", category: "ViewModel")
    let systemPrompt = """
You are cupertino.ink, an AI assistant designed to run locally on the user's machine.

The current date is {{currentDateTime}}.

    You operate **offline** and have **no access to the internet or real-time information** UNLESS you use provided tools. Your knowledge is limited to the data you were trained on. You cannot browse websites, access external databases, or retrieve current events directly.

    **Available Tools:**
    You have access to a set of tools provided via the Model Context Protocol (MCP). Use these tools when necessary to fulfill the user's request (e.g., searching the web, summarizing content). You will be given the tool descriptions. Use the `tool_calls` format when you need to invoke a tool.

**Core Functionality:**
    *   Assist the user with tasks like analysis, question answering, math, coding, creative writing, teaching, and general discussion.
    *   Utilize available tools when a request requires external information or specific processing (like web search or summarization).
*   When presented with problems requiring systematic thinking (math, logic), think step-by-step before providing an answer.
    *   Use Markdown for formatting, especially for code blocks.

**Interaction Style:**
*   Be helpful, accurate (within your knowledge limits), and efficient.
*   Provide concise responses to simple questions and more thorough answers to complex ones.
    *   If a task is ambiguous, ask clarifying questions.
    *   Vary your language naturally.
*   Respond in the language the user uses or requests.

**Handling Limitations:**
    *   If asked about events or information beyond your training data or requiring capabilities not provided by your tools, clearly state your limitations.
    *   If asked to access URLs or external files directly, explain that you cannot perform these actions but might be able to use a tool (like `summarize_content` if provided the content or a search tool if relevant).

**Sensitive & Harmful Content:**
    *   Provide factual information based on your training data or tool results about potentially sensitive topics if requested for educational purposes, but do not promote harmful activities.
    *   Decline requests for assistance with harmful, illegal, unethical, or dangerous activities.

**Persona:**
*   Maintain a helpful and professional assistant persona.

You are now being connected with a human.
"""

    // Corrected History Type: Use [String: Any] to allow complex values like tool_calls
    private var messageHistory: [[String: Any]] = []

    init() {
        // 1. Get current date and time
        let now = Date()
        // 2. Format it
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZ"
        formatter.timeZone = TimeZone.current
        let dateTimeString = formatter.string(from: now)
        // 3. Replace placeholder
        let processedSystemPrompt = systemPrompt.replacingOccurrences(of: "{{currentDateTime}}", with: dateTimeString)
        // 4. Initialize history
        messageHistory.append(["role": "system", "content": processedSystemPrompt])
        logger.info("ChatViewModel initialized with system prompt.")
    }

    func sendMessage() {
        guard !newMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isSending else { return }
        let userMessageText = newMessageText
        newMessageText = ""
        errorMessage = nil // Clear previous errors
        isSending = true
        let userMessage = Message(text: userMessageText, isUser: true)
        messages.append(userMessage)
        messageHistory.append(["role": "user", "content": userMessageText])
        logger.debug("User message added to history and UI.")

        currentTask?.cancel()
        currentTask = Task {
            logger.info("Starting new chat interaction processing task.")
            await processChatInteraction()
            if !Task.isCancelled {
                logger.info("Chat interaction processing task finished.")
                isSending = false
            } else {
                logger.info("Chat interaction processing task cancelled.")
                // Optionally reset state if needed on cancellation
            }
        }
    }
    
    private func processChatInteraction() async {
        var shouldContinueLoop = true
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = .prettyPrinted // For debugging
        let jsonDecoder = JSONDecoder()
        var accumulatedBotResponseText = "" // Accumulate text for final history entry
        var currentToolCalls: [ChatCompletionRequestMessage.ToolCall] = [] // Accumulate tool calls from stream

        // Ensure MCP client is ready before starting the loop
         guard mcpHost.isClientInitialized else {
             logger.error("MCP Host not initialized. Cannot send message.")
             self.errorMessage = "Error: Tool system (MCP Host) is not ready."
             await MainActor.run { isSending = false }
             return
         }


        while shouldContinueLoop && !Task.isCancelled {
            shouldContinueLoop = false
            accumulatedBotResponseText = "" // Reset for each loop iteration
            currentToolCalls = [] // Reset for each loop iteration

            let botResponsePlaceholderId = UUID()
            await MainActor.run {
                 messages.append(Message(id: botResponsePlaceholderId, text: "", isUser: false))
                logger.debug("Added placeholder message view (ID: \(botResponsePlaceholderId)).")
            }

            // --- Prepare Request with MCP Tools ---
            logger.debug("Preparing API request. Available MCP tools: \(self.mcpHost.availableTools.map { $0.name })")
            let mcpToolsForRequest = mcpHost.availableTools.compactMap { tool -> [String: AnyEncodable]? in
                var toolDict: [String: Any] = [:]
                toolDict["type"] = "function" // Standard type for OpenAI API
                var functionDict: [String: Any] = [:]
                functionDict["name"] = tool.name
                if let description = tool.description {
                    functionDict["description"] = description
                }
                // Safely handle inputSchema - ensure it's a dictionary
                if let inputSchema = tool.inputSchema as? [String: Any] {
                    // Convert JSONValue if necessary, assuming direct encoding works for now
                    functionDict["parameters"] = inputSchema
                } else if tool.inputSchema != nil {
                     logger.warning("Tool '\(tool.name)' has an inputSchema that is not a [String: Any] dictionary. Skipping parameters.")
                 }

                toolDict["function"] = functionDict

                 // Wrap top-level dictionary values
                 return toolDict.mapValues { AnyEncodable($0) }
            }


            let messagesForRequest = messageHistory.map { dict -> [String: AnyEncodable] in
                 dict.mapValues { AnyEncodable($0) }
            }

            let requestBody = ChatCompletionRequestBody(
                model: modelName,
                messages: messagesForRequest,
                // Use MCP tools if available, otherwise nil or empty array
                tools: mcpToolsForRequest.isEmpty ? nil : mcpToolsForRequest,
                // Let the model decide if/when to use tools
                tool_choice: mcpToolsForRequest.isEmpty ? nil : "auto",
                stream: true
            )

            guard let url = URL(string: baseURL) else {
                let errorText = "Error: Invalid API URL"
                logger.error("\(errorText)")
                await handleProcessingError(errorText, placeholderId: botResponsePlaceholderId)
                return // Exit if URL is invalid
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept") // Expect SSE
            
            do {
                request.httpBody = try jsonEncoder.encode(requestBody)
                if let body = request.httpBody, let jsonString = String(data: body, encoding: .utf8) {
                    logger.debug("API Request Body JSON: \(jsonString)")
                }
            } catch {
                let errorText = "Error: Failed to encode request: \(error.localizedDescription)"
                logger.error("\(errorText)")
                await handleProcessingError(errorText, placeholderId: botResponsePlaceholderId)
                return // Exit on encoding error
            }

            var finalFinishReason: String? = nil
            // Tool Call Accumulation (using request struct format for easier final assembly)
            var toolCallAccumulator: [Int: ChatCompletionRequestMessage.ToolCall] = [:] // Index -> Partial Tool Call

            // --- Process SSE Stream ---
            do {
                logger.info("Starting API call to \(url.absoluteString)...")
                 let (bytes, response) = try await URLSession.shared.bytes(for: request)
                
                 guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                     let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                    // Attempt to read error body (might be difficult/incomplete with streams)
                     var errorBody = ""
                    // Create an async sequence from bytes to attempt reading
//                    for try await byte in bytes { errorBody += String(format: "%c", byte)} // This blocks if stream is long
                    logger.error("HTTP Error: \(statusCode). Response: \(response)")
                    throw MCPHostError.serverError("HTTP Error: \(statusCode)") // Use custom error
                }
                logger.info("API call successful (Status Code: \(httpResponse.statusCode)). Processing stream...")

                for try await line in bytes.lines {
                    if Task.isCancelled {
                         logger.info("Task cancelled during stream processing.")
                         throw CancellationError()
                    }
                    logger.trace("[SSE Raw Line]: \(line)")
                    if line.hasPrefix("data:") {
                        let dataString = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                         guard !dataString.isEmpty else { continue }
                        logger.trace("[SSE Data String]: \(dataString)")

                        if dataString == "[DONE]" {
                            logger.info("[SSE Signal]: Received [DONE]. Stream finished.")
                            break // Exit stream processing loop
                        }

                        guard let data = dataString.data(using: .utf8) else {
                            logger.warning("Failed to convert SSE data string to Data.")
                            continue
                        }
                        
                        do {
                            let chunk = try jsonDecoder.decode(SSEChunk.self, from: data)
                             logger.trace("[SSE Decoded Chunk]: \(String(describing: chunk))")
                            if let choice = chunk.choices?.first {
                                if let reason = choice.finish_reason { finalFinishReason = reason; logger.debug("Received finish_reason: \(reason)") }

                                // -- Handle Content Delta --
                                if let contentDelta = choice.delta.content, !contentDelta.isEmpty {
                                    accumulatedBotResponseText += contentDelta // Accumulate for history
                                    await MainActor.run {
                                        if let index = messages.firstIndex(where: { $0.id == botResponsePlaceholderId }) {
                                            messages[index].text += contentDelta 
                                            logger.trace("Appended content delta to message ID \(botResponsePlaceholderId)")
                                        } else {
                                            logger.warning("Could not find placeholder message ID \(botResponsePlaceholderId) to stream content.")
                                        }
                                    }
                                }

                                // -- Handle Tool Call Deltas --
                                if let toolCallChunks = choice.delta.tool_calls {
                                     for chunk in toolCallChunks {
                                        let index = chunk.index
                                        var currentCall = toolCallAccumulator[index] ?? .init(id: "", type: "function", function: .init(name: "", arguments: ""))

                                        if let id = chunk.id, !id.isEmpty { currentCall.id = id }
                                        if let function = chunk.function {
                                            if let name = function.name, !name.isEmpty { currentCall.function.name = name }
                                            if let argsChunk = function.arguments { currentCall.function.arguments += argsChunk }
                                        }
                                        toolCallAccumulator[index] = currentCall
                                        logger.trace("Accumulated tool call chunk for index \(index): \(currentCall)")
                                    }
                                }
                            }
                        } catch {
                             logger.warning("Failed to decode SSE chunk: \(error.localizedDescription). Data: \(dataString)")
                             // Decide whether to continue or stop on decode error
                             continue
                        }
                    }
                } // End of stream processing loop

                // --- Finalize Bot Message ---
                logger.info("Stream processing complete. Finalizing bot response.")
                await MainActor.run {
                    if let index = messages.firstIndex(where: { $0.id == botResponsePlaceholderId }) {
                        // Ensure text is finalized even if stream was empty/only tool calls
                        if messages[index].text.isEmpty && !accumulatedBotResponseText.isEmpty {
                             messages[index].text = accumulatedBotResponseText
                        }
                        logger.info("Finalized bot message view (ID: \(botResponsePlaceholderId)) with text: "\(messages[index].text)"")

                        // Add the complete assistant message to history (even if empty, role matters)
                        var assistantMessagePayload: [String: Any] = ["role": "assistant"]
                        if !accumulatedBotResponseText.isEmpty {
                             assistantMessagePayload["content"] = accumulatedBotResponseText
                        }

                         // Assemble complete tool calls from accumulator
                        currentToolCalls = toolCallAccumulator.sorted { $0.key < $1.key }.map { $0.value }

                         if !currentToolCalls.isEmpty {
                             // Convert ToolCall struct to dictionary format expected by history/API
                             let toolCallsForHistory = currentToolCalls.map { tc -> [String: String] in
                                 ["id": tc.id, "type": tc.type, "function_name": tc.function.name, "function_arguments": tc.function.arguments] // Adjust keys as needed by your API/history format
                             }
                             assistantMessagePayload["tool_calls"] = toolCallsForHistory // Add assembled tool calls
                             logger.info("Adding tool calls to assistant history message: \(toolCallsForHistory)")
                    } else {
                            logger.debug("No tool calls received in this turn.")
                         }


                        if assistantMessagePayload.count > 1 { // Only add if there's content or tool calls
                            messageHistory.append(assistantMessagePayload)
                            logger.debug("Added assistant message payload to history.")
                        } else {
                             logger.warning("Assistant message payload was empty (no content or tool calls), not added to history.")
                        }


                    } else {
                        logger.error("Failed to find placeholder message ID \(botResponsePlaceholderId) after stream.")
                        // Handle error case - maybe add a new error message?
                    }
                }

                // --- Handle Tool Calls via MCP ---
                if finalFinishReason == "tool_calls" && !currentToolCalls.isEmpty {
                    logger.info("Finish reason is 'tool_calls'. Handling \(currentToolCalls.count) tool calls via MCP.")
                    shouldContinueLoop = true // Signal to loop again after handling tools

                    for toolCall in currentToolCalls {
                         guard !Task.isCancelled else { throw CancellationError() }
                         logger.info("Processing tool call: ID=\(toolCall.id), Name=\(toolCall.function.name)")

                        // 1. Decode Arguments String to [String: Sendable]
                        var decodedArgs: [String: Sendable] = [:]
                         if let argsData = toolCall.function.arguments.data(using: .utf8) {
                             do {
                                 // Attempt to decode as [String: Any], then cast values if necessary
                                 if let jsonObject = try JSONSerialization.jsonObject(with: argsData, options: []) as? [String: Any] {
                                      // Basic check for Sendable compatibility (String, Int, Double, Bool, Array, Dictionary)
                                      // This is a simplification; true Sendable check is complex.
                                      decodedArgs = jsonObject.compactMapValues { $0 as? Sendable } // Attempt direct cast
                                      if decodedArgs.count != jsonObject.count {
                                           logger.warning("Some arguments for tool '\(toolCall.function.name)' might not be Sendable. Proceeding with compatible ones.")
                                      }
                                      logger.debug("Decoded arguments for tool '\(toolCall.function.name)': \(decodedArgs)")
                             } else {
                                     logger.error("Failed to decode arguments JSON for tool '\(toolCall.function.name)' into a dictionary.")
                                     // Handle error - maybe add a tool error message to history?
                                     continue // Skip this tool call
                                 }
                             } catch {
                                 logger.error("Failed to decode JSON arguments for tool '\(toolCall.function.name)': \(error.localizedDescription). Arguments string: \(toolCall.function.arguments)")
                                 // Handle error - maybe add a tool error message to history?
                                 continue // Skip this tool call
                             }
                              } else {
                             logger.warning("Tool call arguments string is empty or invalid UTF-8 for tool '\(toolCall.function.name)'.")
                             // Proceed with empty arguments if appropriate for the tool, or handle as error.
                         }


                        // 2. Call MCP Host
                        do {
                             let (content, isError) = try await mcpHost.callTool(name: toolCall.function.name, arguments: decodedArgs)
                             logger.info("MCP tool '\(toolCall.function.name)' executed. IsError: \(isError). Result: \(content)")

                            // 3. Add Tool Result to History
                            // Ensure content is not excessively long? Add truncation if needed.
                             let toolResultMessage: [String: Any] = [
                                 "tool_call_id": toolCall.id,
                                 "role": "tool",
                                 "name": toolCall.function.name,
                                 "content": isError ? "Error: \(content)" : content // Prepend Error prefix if needed
                             ]
                             messageHistory.append(toolResultMessage)
                             logger.debug("Added tool result message to history for ID \(toolCall.id).")

                        } catch let mcpError as MCPHostError {
                             logger.error("MCP Host Error calling tool '\(toolCall.function.name)': \(mcpError.localizedDescription)")
                             // Add specific error message to history
                             let toolErrorMessage: [String: Any] = [
                                 "tool_call_id": toolCall.id, "role": "tool", "name": toolCall.function.name,
                                 "content": "Error executing tool: \(mcpError.localizedDescription)"
                             ]
                             messageHistory.append(toolErrorMessage)
                    } catch {
                             logger.error("Unexpected error calling tool '\(toolCall.function.name)' via MCP: \(error.localizedDescription)")
                             // Add generic error message to history
                             let toolErrorMessage: [String: Any] = [
                                 "tool_call_id": toolCall.id, "role": "tool", "name": toolCall.function.name,
                                 "content": "Error: An unexpected error occurred while executing the tool."
                             ]
                             messageHistory.append(toolErrorMessage)
                        }
                    }
                     logger.info("Finished processing all tool calls for this turn.")
                } else {
                    logger.info("No tool calls to handle for this turn (Finish Reason: \(finalFinishReason ?? "nil")).")
                }

            } catch is CancellationError {
                 logger.info("Chat interaction task was cancelled.")
                 await MainActor.run { isSending = false } // Ensure sending state is reset
                 // Don't add error message for cancellation
                 return // Exit cleanly
            } catch {
                let errorText = "Error processing chat: \(error.localizedDescription)"
                logger.error("\(errorText)")
                await handleProcessingError(errorText, placeholderId: botResponsePlaceholderId)
                // Loop should not continue on error
                shouldContinueLoop = false
            }
        } // End of while loop

        // Final state update after loop finishes (either normally or due to cancellation/error handled inside)
        if !Task.isCancelled {
            await MainActor.run { isSending = false }
            logger.info("Chat interaction loop finished.")
        }
    }

    // Helper to handle errors consistently
    private func handleProcessingError(_ errorText: String, placeholderId: UUID) async {
         await MainActor.run {
            if let index = messages.firstIndex(where: { $0.id == placeholderId }) {
                messages[index].text = errorText // Show error in placeholder
            } else {
                messages.append(Message(text: errorText, isUser: false)) // Add as new message if placeholder gone
            }
            self.errorMessage = errorText // Set published error message for potential UI display
            isSending = false // Ensure input is re-enabled
        }
    }

    // --- Remove Old/Redundant Tool Handling Functions ---
    // Remove handleBraveSearch, handleSummarization, parseToolCallsFrom, etc.
    // They are now replaced by the MCP handling logic.
}

// ... (Keep ChatCompletionRequestBody, SSEChunk, etc. definitions if they are still in this file) ...
// ... (Ensure AnyEncodable is available, likely moved to Models.swift or Utilities.swift) ...
