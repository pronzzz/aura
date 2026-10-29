import SwiftUI

/// The expanded notch: tabs flank the physical notch, the selected tab fills the rest.
struct OpenNotchView: View {
    @ObservedObject var viewModel: NotchViewModel

    var body: some View {
        VStack(spacing: 0) {
            OpenHeader(viewModel: viewModel)
                .frame(height: viewModel.notchHeight)

            Group {
                switch viewModel.tab {
                case .nook: NookTab(viewModel: viewModel)
                case .tray: TrayTab(viewModel: viewModel)
                case .tasks: TasksTab()
                case .ask: AskTab(viewModel: viewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 14)
            .transition(.opacity)
            .id(viewModel.tab)
        }
        .foregroundStyle(.white)
    }
}

struct OpenHeader: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var power = PowerService.shared
    @ObservedObject private var tray = TrayStore.shared
    @ObservedObject private var todos = TodoStore.shared

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(NotchTab.allCases) { tab in
                    TabButton(tab: tab, selected: viewModel.tab == tab, badge: badge(for: tab)) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { viewModel.tab = tab }
                    }
                }
            }
            .padding(.leading, 12)

            Spacer(minLength: viewModel.geometry.hasHardwareNotch ? viewModel.notchWidth + 16 : 16)

            HStack(spacing: 6) {
                if power.hasBattery {
                    HStack(spacing: 4) {
                        Text("\(power.level)%")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(AuraStyle.secondary)
                        Image(systemName: power.symbolName)
                            .font(.system(size: 13))
                            .foregroundStyle(power.level <= Pref.int(.lowBatteryThreshold) && !power.isPluggedIn ? .red : .white.opacity(0.85))
                    }
                    .help(power.remainingDescription ?? "Battery")
                }
                IconButton(symbol: "gearshape.fill", size: 12, diameter: 24, tint: .white.opacity(0.8), help: "Aura Settings") {
                    viewModel.close()
                    SettingsWindowController.shared.show()
                }
            }
            .padding(.trailing, 12)
        }
    }

    private func badge(for tab: NotchTab) -> Int {
        switch tab {
        case .tray: return tray.items.count
        case .tasks: return todos.openCount + TimerService.shared.timers.count
        default: return 0
        }
    }
}

private struct TabButton: View {
    let tab: NotchTab
    let selected: Bool
    let badge: Int
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: tab.icon).font(.system(size: 11, weight: .bold))
                if selected {
                    Text(tab.title).font(.system(size: 11, weight: .semibold, design: .rounded))
                } else if badge > 0 {
                    Text("\(badge)").font(.system(size: 9.5, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(AuraStyle.secondary)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.6))
            .background(Capsule().fill(Color.white.opacity(selected ? 0.16 : (hovering ? 0.08 : 0))))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(tab.title)
    }
}
