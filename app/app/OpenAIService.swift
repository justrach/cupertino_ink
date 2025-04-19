import Foundation
import OpenAI // Ensure you've added the 'openai-swift' package

// Structure to mimic OpenAI's Chat message format expected by the library
typealias ChatQueryMessage = OpenAI.ChatQuery.Message

// Structure to represent the result coming from the streaming API
struct ChatStreamResult {
    let id: String // Stream chunk ID
    let content: String? // Content delta
    let isFinal: Bool // Is this the last chunk?
    // Add properties for tool calls if needed later
}


class OpenAIService {
    private let client: OpenAI

    // Singleton or use Dependency Injection
    static let shared = OpenAIService()

    private init() {
        // --- Configuration ---
        // TODO: Replace with your actual endpoint and API key if needed
        // Match the BASE_URL and API_KEY from your Python example
        let config = OpenAI.Configuration(
            token: "not-needed", // Replace if your local server requires one
            host: "localhost:10240", // Your mlxengine server address e.g. "localhost:10240"
            scheme: .http // Use HTTP for local testing, HTTPS for production OpenAI
        )
        
        // TODO: Implement proper tool definitions if required, similar to the Python example
        // let tools = [ToolDefinition(...)]

        self.client = OpenAI(configuration: config)
    }

    // Function to send messages and receive a streaming response
    func sendChatMessageStream(messages: [Message]) async throws -> AsyncThrowingStream<ChatStreamResult, Error> {
        
        // Convert domain `Message` array to the format required by `openai-swift`
        let queryMessages = messages.map { message -> ChatQueryMessage in
            let role: ChatQueryMessage.Role
            switch message.role {
                case .user: role = .user
                case .assistant: role = .assistant
                case .system: role = .system
                case .tool: role = .tool // Assuming Role enum maps directly
            }
            // TODO: Add tool_calls or tool_call_id if handling tool responses
            return ChatQueryMessage(role: role, content: message.content)
        }

        // Prepare the query
        // TODO: Select the appropriate model name from your Python example
        let query = OpenAI.ChatQuery(
            model: "mlx-community/Qwen2.5-7B-Instruct-1M-4bit", // Or Llama-3.1, Mistral-Nemo etc.
            messages: queryMessages,
            temperature: 0.5 // Optional: Adjust creativity
            // TODO: Add 'tools' parameter here if using tools
            // tools: tools,
            // toolChoice: .auto // Or specify a tool
        )

        print("Sending query to OpenAI API: \(query)") // Debugging

        // Return the async stream
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // Start the streaming chat request
                    let stream = try client.chatsStream(query: query)
                    
                    // Iterate over the stream chunks
                    for try await result in stream {
                        // Assuming result provides chunks with content delta
                        // Adapt this based on the actual structure of 'result' from openai-swift
                        if let choice = result.choices.first {
                            let contentDelta = choice.delta.content
                            let isFinished = choice.finishReason != nil // Check if stream indicates completion

                             print("Stream chunk received: content=\(contentDelta ?? "nil"), isFinished=\(isFinished)") // Debugging

                            // Yield the processed chunk to the stream consumer
                            continuation.yield(ChatStreamResult(
                                id: result.id, // Pass through the chunk ID
                                content: contentDelta,
                                isFinal: isFinished
                                // TODO: Extract tool call info if present
                            ))
                        }
                        
                        // Check if the overall stream finished
                        if result.choices.first?.finishReason != nil {
                             print("Stream finished with reason: \(result.choices.first!.finishReason!)") // Debugging
                            continuation.finish()
                            break // Exit the loop once finished
                        }
                    }
                    // If the loop finishes without an error or explicit finish, finish the continuation
                     print("Stream loop completed.")
                    continuation.finish()
                } catch {
                    print("Error during OpenAI stream: \(error)") // Debugging
                    // Propagate the error
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    // TODO: Implement non-streaming version if needed
    // func sendChatMessage(...) async throws -> Message { ... }

    // TODO: Implement tool execution logic if required
    // func executeToolCall(...) -> Message { ... }
} 