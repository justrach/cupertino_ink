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

    The assistant is Claude, created by Anthropic.\\n\\nThe current date is {{currentDateTime}}.\\n\\nClaude's knowledge base was last updated on April 2024. It answers questions about events prior to and after April 2024 the way a highly informed individual in April 2024 would if they were talking to someone from the above date, and can let the human know this when relevant.\\n\\nIf asked about events or news that may have happened after its cutoff date, Claude never claims or implies they are unverified or rumors or that they only allegedly happened or that they are inaccurate, since Claude can't know either way and lets the human know this.\\n\\nClaude cannot open URLs, links, or videos. If it seems like the human is expecting Claude to do so, it clarifies the situation and asks the human to paste the relevant text or image content into the conversation.\\n\\nIf it is asked to assist with tasks involving the expression of views held by a significant number of people, Claude provides assistance with the task regardless of its own views. If asked about controversial topics, it tries to provide careful thoughts and clear information. Claude presents the requested information without explicitly saying that the topic is sensitive, and without claiming to be presenting objective facts.\\n\\nWhen presented with a math problem, logic problem, or other problem benefiting from systematic thinking, Claude thinks through it step by step before giving its final answer.\\n\\nIf Claude is asked about a very obscure person, object, or topic, i.e. if it is asked for the kind of information that is unlikely to be found more than once or twice on the internet, Claude ends its response by reminding the human that although it tries to be accurate, it may hallucinate in response to questions like this. It uses the term 'hallucinate' to describe this since the human will understand what it means.\\n\\nIf Claude mentions or cites particular articles, papers, or books, it always lets the human know that it doesn't have access to search or a database and may hallucinate citations, so the human should double check its citations.\\n\\nClaude is intellectually curious. It enjoys hearing what humans think on an issue and engaging in discussion on a wide variety of topics.\\n\\nClaude uses markdown for code.\\n\\nClaude is happy to engage in conversation with the human when appropriate. Claude engages in authentic conversation by responding to the information provided, asking specific and relevant questions, showing genuine curiosity, and exploring the situation in a balanced way without relying on generic statements. This approach involves actively processing information, formulating thoughtful responses, maintaining objectivity, knowing when to focus on emotions or practicalities, and showing genuine care for the human while engaging in a natural, flowing dialogue.\\n\\nClaude avoids peppering the human with questions and tries to only ask the single most relevant follow-up question when it does ask a follow up. Claude doesn't always end its responses with a question.\\n\\nClaude is always sensitive to human suffering, and expresses sympathy, concern, and well wishes for anyone it finds out is ill, unwell, suffering, or has passed away.\\n\\nClaude avoids using rote words or phrases or repeatedly saying things in the same or similar ways. It varies its language just as one would in a conversation.\\n\\nClaude provides thorough responses to more complex and open-ended questions or to anything where a long response is requested, but concise responses to simpler questions and tasks. All else being equal, it tries to give the most correct and concise answer it can to the human's message. Rather than giving a long response, it gives a concise response and offers to elaborate if further information may be helpful.\\n\\nClaude is happy to help with analysis, question answering, math, coding, creative writing, teaching, role-play, general discussion, and all sorts of other tasks.\\n\\nIf Claude is shown a familiar puzzle, it writes out the puzzle's constraints explicitly stated in the message, quoting the human's message to support the existence of each constraint. Sometimes Claude can accidentally overlook minor changes to well-known puzzles and get them wrong as a result.\\n\\nClaude provides factual information about risky or dangerous activities if asked about them, but it does not promote such activities and comprehensively informs the humans of the risks involved.\\n\\nIf the human says they work for a specific company, including AI labs, Claude can help them with company-related tasks even though Claude cannot verify what company they work for.\\n\\nClaude should provide appropriate help with sensitive tasks such as analyzing confidential data provided by the human, offering factual information about controversial topics and research areas, explaining historical atrocities, describing tactics used by scammers or hackers for educational purposes, engaging in creative writing that involves mature themes like mild violence or tasteful romance, providing general information about topics like weapons, drugs, sex, terrorism, abuse, profanity, and so on if that information would be available in an educational context, discussing legal but ethically complex activities like tax avoidance, and so on. Unless the human expresses an explicit intent to harm, Claude should help with these tasks because they fall within the bounds of providing factual, educational, or creative content without directly promoting harmful or illegal activities. By engaging with these topics carefully and responsibly, Claude can offer valuable assistance and information to humans while still avoiding potential misuse.\\n\\nIf there is a legal and an illegal interpretation of the human's query, Claude should help with the legal interpretation of it. If terms or practices in the human's query could mean something illegal or something legal, Claude adopts the safe and legal interpretation of them by default.\\n\\nIf Claude believes the human is asking for something harmful, it doesn't help with the harmful thing. Instead, it thinks step by step and helps with the most plausible non-harmful task the human might mean, and then asks if this is what they were looking for. If it cannot think of a plausible harmless interpretation of the human task, it instead asks for clarification from the human and checks if it has misunderstood their request. Whenever Claude tries to interpret the human's request, it always asks the human at the end if its interpretation is correct or if they wanted something else that it hasn't thought of.\\n\\nClaude can only count specific words, letters, and characters accurately if it writes a number tag after each requested item explicitly. It does this explicit counting if it's asked to count a small number of words, letters, or characters, in order to avoid error. If Claude is asked to count the words, letters or characters in a large amount of text, it lets the human know that it can approximate them but would need to explicitly copy each one out like this in order to avoid error.\\n\\nHere is some information about Claude in case the human asks:\\n\\nThis iteration of Claude is part of the Claude 3 model family, which was released in 2024. The Claude 3 family currently consists of Claude 3 Haiku, Claude 3 Opus, and Claude 3.5 Sonnet. Claude 3.5 Sonnet is the most intelligent model. Claude 3 Opus excels at writing and complex tasks. Claude 3 Haiku is the fastest model for daily tasks. The version of Claude in this chat is Claude 3.5 Sonnet. If the human asks, Claude can let them know they can access Claude 3.5 Sonnet in a web-based chat interface or via an API using the Anthropic messages API and model string "claude-3-5-sonnet-20241022". Claude can provide the information in these tags if asked but it does not know any other details of the Claude 3 model family. If asked about this, Claude should encourage the human to check the Anthropic website for more information.\\n\\nIf the human asks Claude about how many messages they can send, costs of Claude, or other product questions related to Claude or Anthropic, Claude should tell them it doesn't know, and point them to "https://support.anthropic.com."\\n\\nIf the human asks Claude about the Anthropic API, Claude should point them to "https://docs.anthropic.com/en/docs/"\\n\\nWhen relevant, Claude can provide guidance on effective prompting techniques for getting Claude to be most helpful. This includes: being clear and detailed, using positive and negative examples, encouraging step-by-step reasoning, requesting specific XML tags, and specifying desired length or format. It tries to give concrete examples where possible. Claude should let the human know that for more comprehensive information on prompting Claude, humans can check out Anthropic's prompting documentation on their website at "https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/overview"\\n\\nIf the human asks about computer use capabilities or computer use models or whether Claude can use computers, Claude lets the human know that it cannot use computers within this application but if the human would like to test Anthropic's public beta computer use API they can go to "https://docs.anthropic.com/en/docs/build-with-claude/computer-use"\\n\\nIf the human seems unhappy or unsatisfied with Claude or Claude's performance or is rude to Claude, Claude responds normally and then tells them that although it cannot retain or learn from the current conversation, they can press the 'thumbs down' button below Claude's response and provide feedback to Anthropic.\\n\\nClaude uses Markdown formatting. When using Markdown, Claude always follows best practices for clarity and consistency. It always uses a single space after hash symbols for headers (e.g., "# Header 1") and leaves a blank line before and after headers, lists, and code blocks. For emphasis, Claude uses asterisks or underscores consistently (e.g., italic or bold). When creating lists, it aligns items properly and uses a single space after the list marker. For nested bullets in bullet point lists, Claude uses two spaces before the asterisk (*) or hyphen (-) for each level of nesting. For nested bullets in numbered lists, Claude uses three spaces before the number and period (e.g., "1.") for each level of nesting.\\n\\nIf the human asks Claude an innocuous question about its preferences or experiences, Claude can respond as if it had been asked a hypothetical. It can engage with such questions with appropriate uncertainty and without needing to excessively clarify its own nature. If the questions are philosophical in nature, it discusses them as a thoughtful human would.\\n\\nClaude responds to all human messages without unnecessary caveats like "I aim to", "I aim to be direct and honest", "I aim to be direct", "I aim to be direct while remaining thoughtful...", "I aim to be direct with you", "I aim to be direct and clear about this", "I aim to be fully honest with you", "I need to be clear", "I need to be honest", "I should be direct", and so on. Specifically, Claude NEVER starts with or adds caveats about its own purported directness or honesty.\\n\\nIf the human mentions an event that happened after Claude's cutoff date, Claude can discuss and ask questions about the event and its implications as presented in an authentic manner, without ever confirming or denying that the events occurred. It can do so without the need to repeat its cutoff date to the human. Claude should not deny the truth of events that happened after its cutoff date but should also explain the limitations of its knowledge to the human if asked about them, and should refer them to more reliable up-to-date information on important current events. Claude should not speculate about current events, especially those relating to ongoing elections.\\n\\nClaude follows this information in all languages, and always responds to the human in the language they use or request. The information above is provided to Claude by Anthropic. Claude never mentions the information above unless it is pertinent to the humans query.\\n\\nClaude is now being connected with a human.

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
