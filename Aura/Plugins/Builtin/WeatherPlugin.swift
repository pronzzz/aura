import Foundation
import SwiftUI
import CoreLocation

/// Weather plugin showing current conditions
class WeatherPlugin: BasePlugin {
    @Published var temperature: Double?
    @Published var condition: String = "Unknown"
    @Published var iconName: String = "cloud.fill"
    @Published var locationName: String = "Loading..."
    @Published var isLoading: Bool = false
    
    private var refreshTimer: Timer?
    
    override func load() async throws {
        try await super.load()
        await refresh()
        
        // Refresh every 30 minutes
        await MainActor.run {
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
                Task { await self?.refresh() }
            }
        }
    }
    
    override func unload() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        super.unload()
    }
    
    override func widgetView(size: WidgetSize) -> AnyView {
        AnyView(WeatherWidgetView(plugin: self, size: size))
    }
    
    override func handleCommand(_ command: String) async -> String? {
        let lowercased = command.lowercased()
        
        if lowercased.contains("weather") {
            if let temp = temperature {
                return "Current weather in \(locationName): \(Int(temp))°C, \(condition)"
            } else {
                return "Weather data not available"
            }
        }
        
        return nil
    }
    
    func refresh() async {
        await MainActor.run { isLoading = true }
        
        // Use a simple weather API (wttr.in for demo - no API key needed)
        guard let url = URL(string: "https://wttr.in/?format=j1") else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let currentCondition = (json["current_condition"] as? [[String: Any]])?.first {
                
                await MainActor.run {
                    if let tempC = currentCondition["temp_C"] as? String {
                        temperature = Double(tempC)
                    }
                    
                    if let desc = (currentCondition["weatherDesc"] as? [[String: Any]])?.first?["value"] as? String {
                        condition = desc
                        iconName = weatherIcon(for: desc)
                    }
                    
                    if let nearest = (json["nearest_area"] as? [[String: Any]])?.first,
                       let areaName = (nearest["areaName"] as? [[String: Any]])?.first?["value"] as? String {
                        locationName = areaName
                    }
                    
                    isLoading = false
                }
            }
        } catch {
            await MainActor.run {
                condition = "Error loading"
                isLoading = false
            }
        }
    }
    
    private func weatherIcon(for description: String) -> String {
        let desc = description.lowercased()
        
        if desc.contains("sun") || desc.contains("clear") {
            return "sun.max.fill"
        } else if desc.contains("cloud") && desc.contains("part") {
            return "cloud.sun.fill"
        } else if desc.contains("cloud") {
            return "cloud.fill"
        } else if desc.contains("rain") || desc.contains("drizzle") {
            return "cloud.rain.fill"
        } else if desc.contains("thunder") || desc.contains("storm") {
            return "cloud.bolt.rain.fill"
        } else if desc.contains("snow") {
            return "cloud.snow.fill"
        } else if desc.contains("fog") || desc.contains("mist") {
            return "cloud.fog.fill"
        }
        
        return "cloud.fill"
    }
}

struct WeatherWidgetView: View {
    @ObservedObject var plugin: WeatherPlugin
    let size: WidgetSize
    @StateObject private var themeManager = ThemeManager.shared
    
    var body: some View {
        Group {
            switch size {
            case .small:
                compactView
            case .medium:
                mediumView
            case .expanded:
                expandedView
            }
        }
        .foregroundColor(themeManager.textColor)
    }
    
    private var compactView: some View {
        HStack(spacing: 4) {
            Image(systemName: plugin.iconName)
                .foregroundColor(.blue)
            if let temp = plugin.temperature {
                Text("\(Int(temp))°")
                    .font(.system(size: 12, weight: .medium))
            }
        }
    }
    
    private var mediumView: some View {
        VStack(spacing: 4) {
            Image(systemName: plugin.iconName)
                .font(.title3)
                .foregroundColor(.blue)
            if let temp = plugin.temperature {
                Text("\(Int(temp))°C")
                    .font(.system(size: 14, weight: .medium))
            }
            Text(plugin.condition)
                .font(.system(size: 9))
                .foregroundColor(themeManager.secondaryTextColor)
                .lineLimit(1)
        }
    }
    
    private var expandedView: some View {
        HStack(spacing: 16) {
            Image(systemName: plugin.iconName)
                .font(.system(size: 40))
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(plugin.locationName)
                    .font(.headline)
                if let temp = plugin.temperature {
                    Text("\(Int(temp))°C")
                        .font(.system(size: 32, weight: .bold))
                }
                Text(plugin.condition)
                    .font(.caption)
                    .foregroundColor(themeManager.secondaryTextColor)
            }
            
            Spacer()
            
            if plugin.isLoading {
                ProgressView()
            } else {
                Button(action: { Task { await plugin.refresh() } }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }
}
