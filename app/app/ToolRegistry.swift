import Foundation // Needed for AnyEncodable

// Helper to encode complex dictionary values like tool parameters
// REMOVED: Moved to Models.swift
// struct AnyEncodable: Encodable { ... entire struct ... } 

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

// The availableToolsDict was already moved to Models.swift previously, but we ensure it's not redefined here.
// let availableToolsDict: [[String: AnyEncodable]]? = [findOrderToolDict, getDeliveryDateToolDict] 