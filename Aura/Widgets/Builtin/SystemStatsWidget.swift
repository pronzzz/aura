import SwiftUI
import Darwin

/// System stats widget showing CPU and memory usage
class SystemStatsWidget: AuraWidget {
    let id = UUID()
    let name = "System"
    let iconName = "cpu"
    
    @Published var size: WidgetSize = .medium
    @Published var priority: WidgetPriority = .low
    @Published var isEnabled: Bool = false // Disabled by default
    
    @Published private(set) var cpuUsage: Double = 0
    @Published private(set) var memoryUsage: Double = 0
    @Published private(set) var memoryUsed: UInt64 = 0
    @Published private(set) var memoryTotal: UInt64 = 0
    
    private var timer: Timer?
    private var previousCPUInfo: host_cpu_load_info?
    
    func body(for size: WidgetSize) -> some View {
        SystemStatsWidgetView(
            cpuUsage: cpuUsage,
            memoryUsage: memoryUsage,
            memoryUsed: memoryUsed,
            memoryTotal: memoryTotal,
            size: size
        )
    }
    
    func onAppear() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }
    
    func onDisappear() {
        timer?.invalidate()
        timer = nil
    }
    
    func refresh() {
        updateCPUUsage()
        updateMemoryUsage()
        
        // Update priority if resources are constrained
        if cpuUsage > 80 || memoryUsage > 85 {
            priority = .high
        } else {
            priority = .low
        }
    }
    
    private func updateCPUUsage() {
        var cpuInfo = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        
        let result = withUnsafeMutablePointer(to: &cpuInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else { return }
        
        if let previous = previousCPUInfo {
            let userDiff = Double(cpuInfo.cpu_ticks.0 - previous.cpu_ticks.0)
            let systemDiff = Double(cpuInfo.cpu_ticks.1 - previous.cpu_ticks.1)
            let idleDiff = Double(cpuInfo.cpu_ticks.2 - previous.cpu_ticks.2)
            let niceDiff = Double(cpuInfo.cpu_ticks.3 - previous.cpu_ticks.3)
            
            let totalTicks = userDiff + systemDiff + idleDiff + niceDiff
            if totalTicks > 0 {
                cpuUsage = ((userDiff + systemDiff + niceDiff) / totalTicks) * 100
            }
        }
        
        previousCPUInfo = cpuInfo
    }
    
    private func updateMemoryUsage() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else { return }
        
        let pageSize = UInt64(vm_kernel_page_size)
        
        let active = UInt64(stats.active_count) * pageSize
        let inactive = UInt64(stats.inactive_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        
        memoryUsed = active + wired + compressed
        memoryTotal = ProcessInfo.processInfo.physicalMemory
        
        if memoryTotal > 0 {
            memoryUsage = (Double(memoryUsed) / Double(memoryTotal)) * 100
        }
    }
}

struct SystemStatsWidgetView: View {
    let cpuUsage: Double
    let memoryUsage: Double
    let memoryUsed: UInt64
    let memoryTotal: UInt64
    let size: WidgetSize
    @StateObject private var themeManager = ThemeManager.shared
    
    var body: some View {
        Group {
            switch size {
            case .small:
                Image(systemName: "cpu")
                    .font(.system(size: 14))
            case .medium:
                VStack(spacing: 2) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 16))
                    Text("\(Int(cpuUsage))%")
                        .font(.system(size: 9))
                        .foregroundColor(themeManager.secondaryTextColor)
                }
            case .expanded:
                expandedView
            }
        }
        .foregroundColor(statusColor)
    }
    
    private var expandedView: some View {
        VStack(spacing: 8) {
            // CPU
            HStack {
                Image(systemName: "cpu")
                    .font(.system(size: 14))
                Text("CPU")
                    .font(.system(size: 11))
                Spacer()
                Text("\(Int(cpuUsage))%")
                    .font(.system(size: 11, weight: .medium))
            }
            
            // CPU Bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(themeManager.widgetBackground)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(cpuColor)
                        .frame(width: geometry.size.width * CGFloat(cpuUsage / 100))
                }
            }
            .frame(height: 4)
            
            // Memory
            HStack {
                Image(systemName: "memorychip")
                    .font(.system(size: 14))
                Text("Memory")
                    .font(.system(size: 11))
                Spacer()
                Text(memoryString)
                    .font(.system(size: 11, weight: .medium))
            }
            
            // Memory Bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(themeManager.widgetBackground)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(memoryColor)
                        .frame(width: geometry.size.width * CGFloat(memoryUsage / 100))
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(WidgetBackground())
        .foregroundColor(themeManager.textColor)
    }
    
    private var statusColor: Color {
        if cpuUsage > 80 || memoryUsage > 85 {
            return .orange
        }
        return themeManager.textColor
    }
    
    private var cpuColor: Color {
        switch cpuUsage {
        case 0..<50: return .green
        case 50..<80: return .yellow
        default: return .red
        }
    }
    
    private var memoryColor: Color {
        switch memoryUsage {
        case 0..<60: return .green
        case 60..<85: return .yellow
        default: return .red
        }
    }
    
    private var memoryString: String {
        let usedGB = Double(memoryUsed) / 1_073_741_824
        let totalGB = Double(memoryTotal) / 1_073_741_824
        return String(format: "%.1f/%.0fGB", usedGB, totalGB)
    }
}
