import Foundation // Needed for AnyEncodable

// Helper to encode complex dictionary values like tool parameters
struct AnyEncodable: Encodable {
    private let value: Any

    init(_ value: Any) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let encodable as Encodable:
            // Check if the value itself is Encodable and encode it directly.
            // This requires careful handling to avoid infinite recursion if AnyEncodable wraps itself.
            // A more robust solution might involve type checking against known Encodable types.
            try encodable.encode(to: encoder)
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
             try container.encode(array.map { AnyEncodable($0) })
        case let dictionary as [String: Any]:
             try container.encode(dictionary.mapValues { AnyEncodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: container.codingPath, debugDescription: "Value not encodable"))
        }
    }
}


// --- Tool Definitions (Simple Dictionaries) ---
// Matches the API structure: https://platform.openai.com/docs/api-reference/chat/create#chat-create-tools
let findOrderToolDict: [String: AnyEncodable] = [
    "type": AnyEncodable("function"),
    "function": AnyEncodable([
        "name": AnyEncodable("find_order_by_name"),
        "description": AnyEncodable("Finds a customer's order ID based on their name..."),
        "parameters": AnyEncodable([
            "type": AnyEncodable("object"),
            "properties": AnyEncodable([
                "customer_name": AnyEncodable(["type": AnyEncodable("string"), "description": AnyEncodable("The full name...")])
            ]),
            "required": AnyEncodable(["customer_name"])
        ])
    ])
]

let getDeliveryDateToolDict: [String: AnyEncodable] = [
    "type": AnyEncodable("function"),
    "function": AnyEncodable([
        "name": AnyEncodable("get_delivery_date"),
        "description": AnyEncodable("Get the estimated delivery date..."),
        "parameters": AnyEncodable([
            "type": AnyEncodable("object"),
            "properties": AnyEncodable([
                "order_id": AnyEncodable(["type": AnyEncodable("string"), "description": AnyEncodable("The customer's unique order identifier.")])
            ]),
            "required": AnyEncodable(["order_id"])
        ])
    ])
]

let availableToolsDict: [[String: AnyEncodable]]? = [findOrderToolDict, getDeliveryDateToolDict] 