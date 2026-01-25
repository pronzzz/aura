import SwiftUI

/// Settings view for configuring Aura
struct SettingsView: View {
    @StateObject private var themeManager = ThemeManager.shared
    @AppStorage("showOnAllSpaces") private var showOnAllSpaces = true
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("expandOnHover") private var expandOnHover = true
    
    var body: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            widgetSettings
                .tabItem {
                    Label("Widgets", systemImage: "square.grid.2x2")
                }
            
            appearanceSettings
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }
        }
        .frame(width: 450, height: 300)
        .padding()
    }
    
    // MARK: - General Settings
    
    private var generalSettings: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                Toggle("Show on All Spaces", isOn: $showOnAllSpaces)
                Toggle("Expand on Hover", isOn: $expandOnHover)
            }
            
            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - Widget Settings
    
    private var widgetSettings: some View {
        Form {
            Section("Enabled Widgets") {
                WidgetToggle(name: "Clock", icon: "clock", enabled: .constant(true))
                WidgetToggle(name: "Battery", icon: "battery.100", enabled: .constant(true))
                WidgetToggle(name: "Wi-Fi", icon: "wifi", enabled: .constant(true))
                WidgetToggle(name: "Music", icon: "music.note", enabled: .constant(true))
                WidgetToggle(name: "Calendar", icon: "calendar", enabled: .constant(false))
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - Appearance Settings
    
    private var appearanceSettings: some View {
        Form {
            Section("Theme") {
                Picker("Appearance", selection: .constant("system")) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
            }
            
            Section("Accent Color") {
                HStack {
                    ForEach([Color.blue, .purple, .pink, .orange, .green], id: \.self) { color in
                        Circle()
                            .fill(color)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: themeManager.accentColor == color ? 2 : 0)
                            )
                            .onTapGesture {
                                themeManager.accentColor = color
                            }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Widget Toggle Row

struct WidgetToggle: View {
    let name: String
    let icon: String
    @Binding var enabled: Bool
    
    var body: some View {
        Toggle(isOn: $enabled) {
            Label(name, systemImage: icon)
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}
