import Foundation
import MCP
import os.log // Use os.log for better logging

// Define a custom error type for MCP Host specific errors
// **Separate enum definition from Error conformance**
enum MCPHostError {
    case configurationError(String)
    case serverError(String)
    case clientError(String)
    case toolExecutionError(String)
}

// Conform to LocalizedError for better descriptions
extension MCPHostError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .configurationError(let msg): return "Configuration Error: \(msg)"
        case .serverError(let msg): return "Server Error: \(msg)"
        case .clientError(let msg): return "Client Error: \(msg)"
        case .toolExecutionError(let msg): return "Tool Execution Error: \(msg)"
        }
    }
}

@MainActor
class MCPHost: ObservableObject {
    // Use the correct `Client` type from the SDK
    // `ServerManager` is not part of the basic SDK types shown in the README
    // private let manager: ServerManager? // Keep commented or remove if not managing servers
    private var client: Client? // Use Client, not MCPClient
    private let logger = Logger(subsystem: "com.cupertino_ink.mcp", category: "host")

    // Published properties to expose state to the UI if needed
    // Assuming listTools() returns [Tool], adjust if SDK uses a different type name
    @Published var availableTools: [Tool] = [] // Use Tool, assuming this is the type from MCP module
    @Published var isClientInitialized: Bool = false
    @Published var hostError: Error? = nil

    init() {
        logger.info("Initializing MCPHost...")
        // Initialize the client - connection happens in start()
        self.client = Client(name: "CupertinoInkClient", version: "1.0.0")
        logger.info("MCP Client initialized (name: \(self.client?.name ?? "unknown"), version: \(self.client?.version ?? "unknown"))")
        // Manager initialization removed
    }

    func start(serverConfigURL: URL? = Bundle.main.url(forResource: "servers", withExtension: "json")) async {
        logger.info("Starting MCP Host...")
        hostError = nil // Clear previous errors

        // --- Configuration Loading (Keep for reference, but not used for direct connection) ---
        if let configURL = serverConfigURL {
             logger.info("Server configuration URL found: \(configURL.path). (Currently unused for direct client connection)")
         } else {
             logger.warning("servers.json configuration file not found. Proceeding with direct client connection.")
         }

        // --- Configure and Connect the Client ---
        guard let client = self.client else {
             logger.error("MCP Client was not initialized correctly.")
             self.hostError = MCPHostError.clientError("Client not initialized.") as Error // Explicit cast
             return
         }

        do {
            // *** TEMPORARY TEST: Use StdioTransport to check linking ***
             logger.info("Attempting to use StdioTransport for testing...")
             let transport = StdioTransport()
             // *** REMEMBER TO CHANGE BACK to HTTPClientTransport later ***
//             guard let serverURL = URL(string: "http://localhost:8080/mcp") else { // Placeholder URL
//                 throw MCPHostError.configurationError("Invalid MCP Server URL.")
//             }
//             let transport = HTTPClientTransport(url: serverURL)
//             logger.info("Using HTTP transport to connect to: \(serverURL.absoluteString)")

            // Connect the client to the transport
             logger.info("Connecting MCP Client...")
             try await client.connect(transport: transport)
             logger.info("Client connected to transport. Initializing session...")

            // Initialize the connection (like a handshake)
            let result = try await client.initialize()
            logger.info("Client session initialized successfully: \(String(describing: result))")
            self.isClientInitialized = true

            // Fetch initial tool list
            await fetchAndUpdateTools()

            // Set up listener for server notifications
            // Note: README examples don't explicitly show these notifications on the Client
            // They might be server-side or handled differently. Commenting out for now.
            // await client.onNotification(ServerInfoChangedNotification.self) { ... }
            // await client.onNotification(ToolsListChangedNotification.self) { ... }
            // await client.onNotification(ResourceUpdatedNotification.self) { ... }
            logger.info("Notification listeners setup skipped (Verify client-side notification support in SDK).")


        } catch {
            logger.error("Failed to connect or initialize MCP Client: \(error.localizedDescription)")
            self.hostError = MCPHostError.clientError("Failed to connect/initialize MCP Client: \(error.localizedDescription)") as Error // Explicit cast
            self.isClientInitialized = false
        }
    }

    func fetchAndUpdateTools() async {
        guard let client = client, isClientInitialized else {
            logger.warning("Cannot fetch tools: Client not connected or initialized.")
            return
        }
        logger.info("Fetching available tools from MCP server...")
        do {
            let tools = try await client.listTools()
            self.availableTools = tools
            logger.info("Successfully fetched \(tools.count) tools: \(tools.map { $0.name })")
        } catch {
            logger.error("Failed to list tools: \(error.localizedDescription)")
            self.hostError = MCPHostError.clientError("Failed to list tools: \(error.localizedDescription)") as Error // Explicit cast
            self.availableTools = []
        }
    }

    // --- Helper to convert [String: Sendable] to [String: Value] ---
    private func convertToSendableArgsToValueArgs(_ sendableArgs: [String: Sendable]) -> [String: Value]? {
        var valueArgs: [String: Value] = [:]
        for (key, sendableValue) in sendableArgs {
            if let value = createValue(from: sendableValue) {
                valueArgs[key] = value
            } else {
                logger.error("Could not convert argument '\(key)' of type \(type(of: sendableValue)) to MCP.Value. Skipping argument.")
            }
        }
        return valueArgs
    }

    // Recursive helper to create MCP.Value from common Sendable types
    private func createValue(from sendable: Sendable) -> Value? {
         if let string = sendable as? String {
             return Value.string(string) // Use explicit enum case
         } else if let int = sendable as? Int {
             return Value.integer(int)   // Use explicit enum case
         } else if let double = sendable as? Double {
             return Value.double(double) // Use explicit enum case
         } else if let bool = sendable as? Bool {
             return Value.bool(bool)     // Use explicit enum case
         } else if let array = sendable as? [Sendable] {
             let valueArray = array.compactMap { createValue(from: $0) }
             if valueArray.count == array.count {
                 return Value.array(valueArray) // Use explicit enum case
             }
         } else if let dictionary = sendable as? [String: Sendable] {
             if let valueDict = convertToSendableArgsToValueArgs(dictionary) {
                 return Value.object(valueDict) // Use explicit enum case
             }
         }
         return nil
     }

    func callTool(name: String, arguments: [String: Sendable]) async throws -> (content: String, isError: Bool) {
        guard let client = client, isClientInitialized else {
            logger.error("Cannot call tool '\(name)': Client not connected or initialized.")
            throw MCPHostError.clientError("Client not connected or initialized.")
        }

        logger.info("Calling tool '\(name)' with Sendable arguments: \(arguments)")
        guard let valueArgs = convertToSendableArgsToValueArgs(arguments) else {
            logger.error("Failed to convert arguments for tool '\(name)' to MCP Value type.")
            throw MCPHostError.toolExecutionError("Invalid arguments format for tool '\(name)'.")
        }
        logger.info("Calling tool '\(name)' with MCP Value arguments (types converted).") // Simplified log

        do {
            let (contentItems, isError) = try await client.callTool(name: name, arguments: valueArgs)

            // Convert [Content] to a single String
            var resultString = ""
             for item in contentItems {
                 switch item {
                 case .text(let text):
                     resultString += text
                 case .image(let data, let mimeType, let metadata):
                     resultString += "[Image data: \(data.count) bytes, type: \(mimeType ?? "unknown")]"
                     if let meta = metadata { resultString += " Metadata: \(meta)" }
                 // Add default case to make switch exhaustive
                 default:
                     logger.warning("Unhandled MCP.Content type received: \(item)")
                     resultString += "[Unhandled Content Type]"
                 }
             }
             resultString = resultString.trimmingCharacters(in: .whitespacesAndNewlines)
             if resultString.isEmpty && !contentItems.isEmpty {
                  resultString = "[Tool returned non-text or unhandled content]"
             }

            // Simplify logging and explicitly create return tuple
            let logMessage = "Tool '\(name)' call result - IsError: \(isError), Stringified Content Length: \(resultString.count)"
            logger.info("\(logMessage)")
            let resultTuple: (content: String, isError: Bool) = (resultString, isError)
            return resultTuple

        } catch {
             logger.error("Failed to call tool '\(name)': \(error.localizedDescription)")
            if let mcpError = error as? MCPError {
                 throw mcpError
             } else {
                 throw MCPHostError.toolExecutionError("Failed to execute tool '\(name)': \(error.localizedDescription)")
             }
        }
    }

    // Example function to subscribe to resource updates (if needed)
    // Needs verification if client supports onNotification directly
    // func subscribeToResource(uri: String) async { ... }

    func stop() async {
        logger.info("Stopping MCP Host...")
        if let client = client {
            logger.info("MCP Client instance cleanup relies on ARC or transport disconnection.")
            self.isClientInitialized = false
            self.availableTools = []
        }
    }
} 