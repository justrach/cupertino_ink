import Foundation
import SwiftUI // Needed for ObservableObject

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

// --- API Request/Response Structs (Encodable & Decodable) ---

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

// Helper Structs for JSON Decoding Tool Arguments
struct ToolCallArgsFindOrder: Decodable {
    let customer_name: String
}

struct ToolCallArgsGetDelivery: Decodable {
    let order_id: String
}

// Re-add necessary structs for parsing (if needed elsewhere, keep public)
// This might be redundant if client-side parsing isn't implemented in Swift yet.
// Keep it for potential future use or remove if definitely not needed.
struct ParsedToolCall {
    let id: String = "call_\(UUID().uuidString.prefix(12))"
    let type: String = "function"
    let function: FunctionCall
    struct FunctionCall {
        let name: String
        let arguments: [String: String] // Assuming arguments are decoded elsewhere
    }
}

// --- AnyEncodable Helper (Moved from ToolRegistry) ---
// Needed by ChatCompletionRequestBody
struct AnyEncodable: Encodable {
    private let value: Any

    init(_ value: Any) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let string as String:
            try container.encode(string)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let bool as Bool:
            try container.encode(bool)
        case let array as [Any]:
            try container.encode(array.map { AnyEncodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyEncodable($0) })
        case is NSNull: // Handle NSNull for nil values in history
             try container.encodeNil()
        default:
            // Attempt to encode dictionary directly if possible
             if let encodableDict = value as? [String: Encodable] {
                 // This path might require more specific handling or custom encoders
                 // depending on the actual dictionary content.
                 // For simple cases, try encoding mapValues.
                 // If it contains complex non-Encodable types, this will fail.
                  print("Encoding dictionary: \(encodableDict)") // Debug print
                 try container.encode(encodableDict.mapValues { AnyEncodable($0) })

            } else {
                throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: container.codingPath, debugDescription: "Unsupported type for AnyEncodable"))
            }
        }
    }
}

// Required by ChatViewModel, but defined outside models
// Moved here for compilation temporarily, will move to ToolRegistry later
let availableToolsDict: [[String: AnyEncodable]] = [
    [
        "type": AnyEncodable("function"),
        "function": AnyEncodable([
            "name": "find_order_by_name",
            "description": "Finds a customer's order ID based on their name. Call this first when a customer asks about their order but doesn't provide an order ID.",
            "parameters": [
                "type": "object",
                "properties": [
                    "customer_name": ["type": "string", "description": "The full name of the customer."]
                ],
                "required": ["customer_name"]
            ]
        ] as [String : Any]) // Cast inner dictionary
    ],
    [
        "type": AnyEncodable("function"),
        "function": AnyEncodable([
            "name": "get_delivery_date",
            "description": "Get the estimated delivery date for a specific order ID. Only call this *after* you have obtained the order ID.",
            "parameters": [
                "type": "object",
                "properties": [
                    "order_id": ["type": "string", "description": "The customer's unique order identifier."]
                ],
                "required": ["order_id"]
            ]
        ] as [String : Any]) // Cast inner dictionary
    ]
]

// --- Color Definitions (Moved from original ContentView) ---
// Define custom colors
// REMOVED - Defined in Color+Extensions.swift
// extension Color {
//     static let nuevoOrange = Color("NuevoOrange") // Ensure this color exists in Assets.xcassets
//     static let nuevoDarkGray = Color("NuevoDarkGray") // Ensure this color exists in Assets.xcassets
//     static let nuevoLightGray = Color("NuevoLightGray") // Ensure this color exists in Assets.xcassets
//     static let nuevoInputBackground = Color("NuevoInputBackground") // Ensure this color exists in Assets.xcassets
//     static let nuevoStroke = Color("NuevoStroke") // Ensure this color exists in Assets.xcassets
// } 