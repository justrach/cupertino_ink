import Foundation
import Combine
import OSLog // For logging

@MainActor // Ensure published properties are updated on the main thread
class MLXEngineController: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var statusMessage: String = "Engine stopped."

    private var process: Process?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "MLXEngine")

    // Function to find the executable path (simple version assumes PATH) - REMOVING THIS
    /*
    private func findExecutable() -> URL? {
        // Simple approach: Assume mlxengine is in PATH
        // More robust: Run "/usr/bin/which mlxengine" to get the full path
        // Even better: Allow user to configure the path in settings
        // For now, let Process search the PATH by default.
        // We construct a URL assuming it's a command, Process will search PATH.
        // Note: Directly using "mlxengine" might not work if Process doesn't inherit the shell's PATH correctly.
        // Using /usr/bin/env might be more reliable to ask the standard environment to find it.

        // Let's try using /usr/bin/env to find mlxengine in the user's PATH
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["which", "mlxengine"]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
                logger.info("Found mlxengine at: \(path)")
                return URL(fileURLWithPath: path)
            } else {
                 logger.error("'which mlxengine' did not return a path.")
                return nil
            }
        } catch {
            logger.error("Failed to run 'which mlxengine': \(error.localizedDescription)")
            return nil
        }
    }
    */

    func startEngine() {
        guard !isRunning else {
            logger.warning("Attempted to start engine while already running.")
            statusMessage = "Engine already running."
            return
        }

        // --- Directly specify the full path --- 
        let executablePath = "/Users/rachpradhan/.uv_env/base/bin/mlxengine"
        let executableURL = URL(fileURLWithPath: executablePath)

        // Check if the executable actually exists at the path
        guard FileManager.default.fileExists(atPath: executablePath), 
              FileManager.default.isExecutableFile(atPath: executablePath) else {
            statusMessage = "Error: mlxengine not found or not executable at \(executablePath)"
            logger.error("mlxengine executable not found or not executable at specified path: \(executablePath)")
            return
        }
        // --- End direct path specification ---

        // guard let executableURL = findExecutable() else { // Old code using findExecutable
        //     statusMessage = "Error: mlxengine not found in PATH."
        //     logger.error("mlxengine executable not found.")
        //     return
        // }

        process = Process()
        process?.executableURL = executableURL
        // Add arguments if mlxengine needs any:
        // process?.arguments = ["--some-arg", "value"]

        // Optional: Capture output
        let outputPipe = Pipe()
        process?.standardOutput = outputPipe
        let errorPipe = Pipe()
        process?.standardError = errorPipe

        // Handle termination - update state when process finishes
        process?.terminationHandler = { [weak self] _ in
            Task { @MainActor in // Ensure UI updates are on main thread
                 self?.logger.info("mlxengine process terminated.")
                 self?.isRunning = false
                 self?.statusMessage = "Engine stopped."
                 self?.process = nil // Release the process object
            }
        }

        do {
            logger.info("Starting mlxengine process...")
            try process?.run()
            isRunning = true
            statusMessage = "Engine running..."
            logger.info("mlxengine process started successfully.")

            // Optional: Read output asynchronously (example)
            // outputPipe.fileHandleForReading.readabilityHandler = { handle in
            //     let data = handle.availableData
            //     if data.isEmpty { // EOF
            //         handle.readabilityHandler = nil
            //     } else if let line = String(data: data, encoding: .utf8) {
            //         DispatchQueue.main.async {
            //              self.statusMessage = "Engine output: \(line.prefix(100))"
            //              self.logger.debug("mlxengine stdout: \(line)")
            //         }
            //     }
            // }
            // errorPipe.fileHandleForReading.readabilityHandler = { handle in ... }

        } catch {
            logger.error("Failed to start mlxengine: \(error.localizedDescription)")
            statusMessage = "Error starting engine: \(error.localizedDescription)"
            process = nil
            isRunning = false
        }
    }

    func stopEngine() {
        guard isRunning, let process = process else {
            logger.warning("Attempted to stop engine while not running or process is nil.")
            // Ensure state consistency
            if isRunning || self.process != nil {
                 isRunning = false
                 self.process = nil
                 statusMessage = "Engine stopped (force cleanup)."
            }
            return
        }

        logger.info("Stopping mlxengine process...")
        // Send SIGTERM. You could use interrupt() first for SIGINT if preferred.
        process.terminate()
        // The terminationHandler will update the state.
        // We might want a timeout here in case termination hangs.
    }

    // Ensure termination on app quit
    func cleanup() {
         logger.info("Cleaning up MLXEngineController...")
         stopEngine()
    }
} 