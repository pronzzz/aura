import Foundation
import os.signpost
import QuartzCore

/// Performance monitoring and optimization utilities
class PerformanceMonitor: ObservableObject {
    static let shared = PerformanceMonitor()
    
    @Published var cpuUsage: Double = 0.0
    @Published var memoryUsage: Double = 0.0
    @Published var isPerformanceMode: Bool = false
    
    private let logger = Logger(subsystem: "com.pranavdwivedi.aura", category: "Performance")
    private let signpostLog = OSLog(subsystem: "com.pranavdwivedi.aura", category: .pointsOfInterest)
    private var monitorTimer: Timer?
    
    // Performance thresholds
    private let maxCPUUsage: Double = 5.0  // 5% max
    private let maxMemoryMB: Double = 100.0  // 100MB max
    
    private init() {
        startMonitoring()
    }
    
    // MARK: - Monitoring
    
    func startMonitoring() {
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.collectMetrics()
        }
    }
    
    func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
    }
    
    private func collectMetrics() {
        cpuUsage = getCurrentCPUUsage()
        memoryUsage = getCurrentMemoryUsage()
        
        // Log if exceeding thresholds
        if cpuUsage > maxCPUUsage {
            logger.warning("CPU usage elevated: \(self.cpuUsage, privacy: .public)%")
        }
        
        if memoryUsage > maxMemoryMB {
            logger.warning("Memory usage elevated: \(self.memoryUsage, privacy: .public)MB")
        }
    }
    
    // MARK: - Performance Mode
    
    /// Enable performance mode to reduce resource usage
    func enablePerformanceMode() {
        isPerformanceMode = true
        
        // Reduce widget update frequency
        NotificationCenter.default.post(name: .performanceModeChanged, object: true)
        
        // Disable non-essential features
        logger.info("Performance mode enabled")
    }
    
    func disablePerformanceMode() {
        isPerformanceMode = false
        NotificationCenter.default.post(name: .performanceModeChanged, object: false)
        logger.info("Performance mode disabled")
    }
    
    // MARK: - Signpost Helpers
    
    /// Begin a performance measurement span
    func beginMeasure(_ name: StaticString) -> OSSignpostID {
        let id = OSSignpostID(log: signpostLog)
        os_signpost(.begin, log: signpostLog, name: name, signpostID: id)
        return id
    }
    
    /// End a performance measurement span
    func endMeasure(_ name: StaticString, id: OSSignpostID) {
        os_signpost(.end, log: signpostLog, name: name, signpostID: id)
    }
    
    // MARK: - Resource Optimization
    
    /// Pause expensive operations when app is in background
    func appDidEnterBackground() {
        // Notify other components to reduce their update frequency
        NotificationCenter.default.post(name: .performanceModeChanged, object: true)
        logger.info("Entered background - pausing updates")
    }
    
    func appWillEnterForeground() {
        NotificationCenter.default.post(name: .performanceModeChanged, object: false)
        logger.info("Entering foreground - resuming updates")
    }
    
    // MARK: - Metrics Collection
    
    private func getCurrentCPUUsage() -> Double {
        var threadsList: thread_act_array_t?
        var threadCount = mach_msg_type_number_t()
        
        guard task_threads(mach_task_self_, &threadsList, &threadCount) == KERN_SUCCESS,
              let threads = threadsList else {
            return 0.0
        }
        
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), vm_size_t(threadCount) * vm_size_t(MemoryLayout<thread_t>.stride))
        }
        
        var totalCPU: Double = 0.0
        
        for i in 0..<Int(threadCount) {
            var info = thread_basic_info()
            var count = mach_msg_type_number_t(THREAD_INFO_MAX)
            
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
                }
            }
            
            if result == KERN_SUCCESS && (info.flags & TH_FLAGS_IDLE) == 0 {
                totalCPU += Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
            }
        }
        
        return totalCPU
    }
    
    private func getCurrentMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            return Double(info.resident_size) / 1024.0 / 1024.0
        }
        
        return 0.0
    }
}

extension Notification.Name {
    static let performanceModeChanged = Notification.Name("performanceModeChanged")
}
