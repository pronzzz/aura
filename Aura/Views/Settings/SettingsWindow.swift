import AppKit
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, notch, activities, media, tray, shortcuts, assistant, automation, permissions, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .notch: return "Notch & Gestures"
        case .activities: return "Live Activities"
        case .media: return "Media"
        case .tray: return "Tray"
        case .shortcuts: return "Shortcuts"
        case .assistant: return "Assistant"
        case .automation: return "Automation"
        case .permissions: return "Permissions"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .notch: return "capsule.tophalf.filled"
        case .activities: return "waveform"
        case .media: return "music.note"
        case .tray: return "tray.full.fill"
        case .shortcuts: return "square.stack.3d.up.fill"
        case .assistant: return "sparkles"
        case .automation: return "bolt.horizontal.fill"
        case .permissions: return "lock.shield.fill"
        case .about: return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .general: return .gray
        case .notch: return .black
        case .activities: return .pink
        case .media: return .red
        case .tray: return .blue
        case .shortcuts: return .indigo
        case .assistant: return .purple
        case .automation: return .orange
        case .permissions: return .green
        case .about: return .teal
        }
    }
}

final class SettingsModel: ObservableObject {
    @Published var section: SettingsSection = .general
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private let model = SettingsModel()

    func show(section: SettingsSection? = nil) {
        if let section { model.section = section }
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(model: model))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Aura Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
            window.setContentSize(NSSize(width: 760, height: 540))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $model.section) { section in
                Label {
                    Text(section.title)
                } icon: {
                    Image(systemName: section.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(section.color.gradient))
                }
                .tag(section)
                .padding(.vertical, 2)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 210, max: 240)
        } detail: {
            Group {
                switch model.section {
                case .general: GeneralSettings()
                case .notch: NotchSettings()
                case .activities: ActivitySettings()
                case .media: MediaSettings()
                case .tray: TraySettings()
                case .shortcuts: ShortcutsSettings()
                case .assistant: AssistantSettings()
                case .automation: AutomationSettings()
                case .permissions: PermissionsSettings()
                case .about: AboutSettings()
                }
            }
            .formStyle(.grouped)
            .navigationTitle(model.section.title)
        }
        .frame(minWidth: 720, minHeight: 500)
    }
}
