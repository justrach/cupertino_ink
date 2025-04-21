import SwiftUI
import Combine
import IOKit.graphics // For VRAM
import Darwin // For mach_host, etc.

class SystemMonitor: ObservableObject {
    @Published var totalVRAMMB: Double? = nil
    @Published var systemCPUUsage: Double? = nil // Value between 0.0 and 1.0

    private var timerSubscription: Cancellable?
    private var previousCPULoadInfo: host_cpu_load_info?

    // MARK: - Public Methods

    func startMonitoring(interval: TimeInterval = 2.0) {
        stopMonitoring() // Ensure no existing timer is running

        // Fetch initial values immediately
        fetchTotalVRAM()
        fetchSystemCPUUsage() // Initial fetch requires two points in time, so first reading might be nil

        timerSubscription = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.fetchTotalVRAM() // VRAM usually doesn't change, but good practice
                self?.fetchSystemCPUUsage()
            }
    }

    func stopMonitoring() {
        timerSubscription?.cancel()
        timerSubscription = nil
        previousCPULoadInfo = nil // Reset previous load info
    }

    // MARK: - Private Fetching Methods

    private func fetchTotalVRAM() {
        DispatchQueue.global(qos: .utility).async {
            // Check for Apple Silicon first
            if self.isAppleSilicon() {
                 // On Apple Silicon, VRAM is unified memory. Reporting total system RAM might be 
                 // an option, but it's not strictly "VRAM". Let's report it as unified for now.
                 // We could also query Metal for recommendedMaxWorkingSetSize, but that's more complex.
                 let totalSystemMemoryMB = self.getTotalSystemMemoryMB()
                 DispatchQueue.main.async {
                     // Update the state to indicate unified memory, maybe include system total?
                     // For now, setting totalVRAMMB might be misleading. Let's refine this later.
                     // Perhaps add a separate @Published var memoryType: String? = nil
                     self.totalVRAMMB = totalSystemMemoryMB // Tentatively report total system memory
                     // Or: self.totalVRAMMB = nil // Or report nil/unknown for dedicated VRAM?
                     // Or add a specific state like: self.isUnifiedMemory = true 
                     print("Detected Apple Silicon with Unified Memory. Reporting total system RAM: \(totalSystemMemoryMB ?? 0) MB")
                 }
                 return // Stop here for Apple Silicon
            }
            
            // --- Logic for Intel/AMD (Dedicated VRAM) below --- 
            var totalVRAM: UInt64 = 0 // Initialize to 0
            var foundVRAM = false

            // IOKit query to find graphics devices
            var iterator: io_iterator_t = 0
            // Try IOGraphicsAccelerator2 first, then IOPCIDevice as a fallback
            let matchingDict = IOServiceMatching("IOGraphicsAccelerator2") 
            var kernResult = IOServiceGetMatchingServices(kIOMasterPortDefault, matchingDict, &iterator)
            
            if kernResult != KERN_SUCCESS || iterator == 0 {
                print("Warning: Failed to get IOGraphicsAccelerator2 services, trying IOPCIDevice...")
                IOObjectRelease(iterator) // Release previous iterator if it existed
                iterator = 0
                // Pass the dictionary directly (it's Optional)
                let fallbackDict = IOServiceMatching("IOPCIDevice") 
                kernResult = IOServiceGetMatchingServices(kIOMasterPortDefault, fallbackDict, &iterator)
            }

            guard kernResult == KERN_SUCCESS, iterator != 0 else {
                print("Error: Failed to get any graphics/PCI device services.")
                DispatchQueue.main.async { self.totalVRAMMB = nil } // Update UI on failure
                return
            }

            var service = IOIteratorNext(iterator)
            while service != 0 {
                var properties: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                   let props = properties?.takeRetainedValue() as? [String: Any] {
                    
                    // Check device class, filter for Display/VGA controllers if using IOPCIDevice
                    if let deviceClass = props[kIOClassKey] as? String, 
                       deviceClass == "IOPCIDevice", // Only check VRAM if we fell back to IOPCIDevice
                       let classCode = props["class-code"] as? Data,
                       classCode.count >= 3 {
                        // Check if it's a VGA-compatible controller (0x03XXXX)
                        let codeBytes = [UInt8](classCode)
                        if codeBytes[2] != 0x03 { // Index 2 is base class (0x03 for Display)
                            IOObjectRelease(service)
                            service = IOIteratorNext(iterator)
                            continue // Skip non-display devices if using IOPCIDevice fallback
                        }
                    }
                    
                    // Look for VRAM properties (add more keys)
                    let vramKeys = ["VRAM,totalMB", "VRAM,totalBytes", "vram_size", "gpu-vram-size"]
                    for key in vramKeys {
                        if let vramMB = props[key] as? Int {
                            totalVRAM += UInt64(vramMB)
                            foundVRAM = true
                            break // Found VRAM for this device using MB key
                        } else if let vramBytes = props[key] as? Int {
                            totalVRAM += UInt64(vramBytes / (1024 * 1024))
                            foundVRAM = true
                            break // Found VRAM for this device using Bytes key
                        }
                    }
                }
                properties?.release()
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            IOObjectRelease(iterator)
            
            // Update on main thread
            DispatchQueue.main.async {
                if foundVRAM && totalVRAM > 0 { // Ensure we actually found something > 0
                    self.totalVRAMMB = Double(totalVRAM)
                } else {
                    print("Could not determine dedicated VRAM size from IOKit properties.")
                    self.totalVRAMMB = nil // Indicate failure or unknown
                }
            }
        }
    }

    private func fetchSystemCPUUsage() {
        DispatchQueue.global(qos: .utility).async {
            var currentLoadInfo = host_cpu_load_info()
            var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
            let host = mach_host_self()

            // Cast the pointer to the expected host_info_t type
            let kernReturn = withUnsafeMutablePointer(to: &currentLoadInfo) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { pointer in
                    host_statistics(host, HOST_CPU_LOAD_INFO, pointer, &size)
                }
            }
            
            guard kernReturn == KERN_SUCCESS else {
                print("Error: host_statistics failed - \(String(cString: mach_error_string(kernReturn)))")
                return
            }

            guard let previousLoadInfo = self.previousCPULoadInfo else {
                // Need previous data point to calculate delta
                self.previousCPULoadInfo = currentLoadInfo
                return
            }

            // Calculate deltas
            let userTicksDelta = Double(currentLoadInfo.cpu_ticks.0 - previousLoadInfo.cpu_ticks.0)
            let systemTicksDelta = Double(currentLoadInfo.cpu_ticks.1 - previousLoadInfo.cpu_ticks.1)
            let idleTicksDelta = Double(currentLoadInfo.cpu_ticks.2 - previousLoadInfo.cpu_ticks.2)
            let niceTicksDelta = Double(currentLoadInfo.cpu_ticks.3 - previousLoadInfo.cpu_ticks.3) // Usually 0 on macOS

            let totalTicksDelta = userTicksDelta + systemTicksDelta + idleTicksDelta + niceTicksDelta

            var usage: Double? = nil
            if totalTicksDelta > 0 {
                let usedTicksDelta = userTicksDelta + systemTicksDelta + niceTicksDelta
                usage = usedTicksDelta / totalTicksDelta
            }

            // Store current for next calculation and update published property
            self.previousCPULoadInfo = currentLoadInfo
            
            DispatchQueue.main.async {
                self.systemCPUUsage = usage
            }
        }
    }

    // Helper to check for Apple Silicon
    private func isAppleSilicon() -> Bool {
        var systeminfo = utsname()
        uname(&systeminfo)
        
        // Calculate the size beforehand to avoid overlapping access
        let machineMirror = Mirror(reflecting: systeminfo.machine)
        let machineSize = machineMirror.children.reduce(0) { $0 + MemoryLayout.size(ofValue: $1.value) } // Size of the tuple elements

        let machine = withUnsafePointer(to: &systeminfo.machine) {
            // Use the pre-calculated size for capacity
            $0.withMemoryRebound(to: CChar.self, capacity: machineSize) { ptr in 
                String(cString: ptr)
            }
        }
        return machine.starts(with: "arm64") // Basic check for ARM architecture
    }

    // Helper to get total system memory (useful for Apple Silicon context)
    private func getTotalSystemMemoryMB() -> Double? {
        var memorySize: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        if sysctlbyname("hw.memsize", &memorySize, &size, nil, 0) == 0 {
            return Double(memorySize / (1024 * 1024))
        }
        return nil
    }
} 