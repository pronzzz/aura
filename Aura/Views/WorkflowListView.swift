import SwiftUI

/// View for listing and managing workflows
struct WorkflowListView: View {
    @ObservedObject var workflowEngine = WorkflowEngine.shared
    @StateObject private var themeManager = ThemeManager.shared
    @State private var showingAddSheet = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Workflows")
                    .font(.headline)
                
                Spacer()
                
                Button(action: { showingAddSheet = true }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.purple)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            if workflowEngine.workflows.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bolt.circle")
                        .font(.system(size: 40))
                        .foregroundColor(themeManager.secondaryTextColor)
                    
                    Text("No Workflows")
                        .font(.headline)
                    
                    Text("Create automations that respond to events")
                        .font(.caption)
                        .foregroundColor(themeManager.secondaryTextColor)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(workflowEngine.workflows) { workflow in
                            WorkflowRow(workflow: workflow)
                        }
                    }
                    .padding()
                }
            }
        }
        .foregroundColor(themeManager.textColor)
        .sheet(isPresented: $showingAddSheet) {
            WorkflowEditorView(isPresented: $showingAddSheet)
        }
    }
}

struct WorkflowRow: View {
    let workflow: Workflow
    @ObservedObject var workflowEngine = WorkflowEngine.shared
    @StateObject private var themeManager = ThemeManager.shared
    
    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(workflow.isEnabled ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            
            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(workflow.name)
                    .font(.system(size: 13, weight: .medium))
                
                HStack(spacing: 4) {
                    Image(systemName: triggerIcon)
                        .font(.system(size: 9))
                    Text(workflow.trigger.displayName)
                        .font(.system(size: 10))
                }
                .foregroundColor(themeManager.secondaryTextColor)
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 8) {
                // Run manually
                if case .manual = workflow.trigger {
                    Button(action: { workflowEngine.runWorkflow(workflow) }) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
                
                // Toggle
                Toggle("", isOn: Binding(
                    get: { workflow.isEnabled },
                    set: { _ in workflowEngine.toggleWorkflow(id: workflow.id) }
                ))
                .toggleStyle(.switch)
                .scaleEffect(0.7)
            }
        }
        .padding(10)
        .background(themeManager.widgetBackground)
        .cornerRadius(8)
    }
    
    private var triggerIcon: String {
        switch workflow.trigger {
        case .appLaunched, .appClosed: return "app.badge"
        case .timeOfDay: return "clock"
        case .batteryLevel, .batteryCharging: return "battery.50"
        case .focusModeChanged: return "moon.fill"
        case .meetingStarting: return "calendar"
        case .screenShareStarted, .screenShareEnded: return "rectangle.inset.filled.and.person.filled"
        case .hotkey: return "command"
        case .manual: return "hand.tap"
        }
    }
}

struct WorkflowEditorView: View {
    @Binding var isPresented: Bool
    @ObservedObject var workflowEngine = WorkflowEngine.shared
    @StateObject private var themeManager = ThemeManager.shared
    
    @State private var name = ""
    @State private var selectedTrigger: TriggerType = .manual
    @State private var selectedActions: Set<ActionType> = []
    
    enum TriggerType: String, CaseIterable {
        case manual = "Manual"
        case appLaunched = "App Launched"
        case batteryLow = "Battery Low"
        case focusOn = "Focus Mode On"
        case screenShare = "Screen Share Started"
    }
    
    enum ActionType: String, CaseIterable {
        case expandNotch = "Expand Notch"
        case collapseNotch = "Collapse Notch"
        case showMusic = "Show Music Widget"
        case hideMusic = "Hide Music Widget"
        case showCalendar = "Show Calendar Widget"
        case notify = "Show Notification"
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Text("New Workflow")
                .font(.headline)
            
            TextField("Workflow Name", text: $name)
                .textFieldStyle(.roundedBorder)
            
            // Trigger picker
            VStack(alignment: .leading, spacing: 4) {
                Text("Trigger")
                    .font(.caption)
                    .foregroundColor(themeManager.secondaryTextColor)
                
                Picker("Trigger", selection: $selectedTrigger) {
                    ForEach(TriggerType.allCases, id: \.self) { trigger in
                        Text(trigger.rawValue).tag(trigger)
                    }
                }
                .pickerStyle(.menu)
            }
            
            // Actions
            VStack(alignment: .leading, spacing: 4) {
                Text("Actions")
                    .font(.caption)
                    .foregroundColor(themeManager.secondaryTextColor)
                
                ForEach(ActionType.allCases, id: \.self) { action in
                    HStack {
                        Image(systemName: selectedActions.contains(action) ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(selectedActions.contains(action) ? .purple : themeManager.secondaryTextColor)
                        Text(action.rawValue)
                    }
                    .onTapGesture {
                        if selectedActions.contains(action) {
                            selectedActions.remove(action)
                        } else {
                            selectedActions.insert(action)
                        }
                    }
                }
            }
            
            Spacer()
            
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                
                Spacer()
                
                Button("Create") {
                    createWorkflow()
                    isPresented = false
                }
                .disabled(name.isEmpty || selectedActions.isEmpty)
            }
        }
        .padding()
        .frame(width: 300, height: 400)
        .foregroundColor(themeManager.textColor)
    }
    
    private func createWorkflow() {
        let trigger: WorkflowTrigger = switch selectedTrigger {
        case .manual: .manual
        case .appLaunched: .appLaunched(bundleId: "com.apple.dt.Xcode")
        case .batteryLow: .batteryLevel(below: 20)
        case .focusOn: .focusModeChanged(active: true)
        case .screenShare: .screenShareStarted
        }
        
        var actions: [WorkflowAction] = []
        for action in selectedActions {
            switch action {
            case .expandNotch: actions.append(.expandNotch)
            case .collapseNotch: actions.append(.collapseNotch)
            case .showMusic: actions.append(.showWidget(widgetName: "Music"))
            case .hideMusic: actions.append(.hideWidget(widgetName: "Music"))
            case .showCalendar: actions.append(.showWidget(widgetName: "Calendar"))
            case .notify: actions.append(.showNotification(title: name, body: "Workflow executed"))
            }
        }
        
        let workflow = Workflow(name: name, trigger: trigger, actions: actions)
        workflowEngine.addWorkflow(workflow)
    }
}

#Preview {
    WorkflowListView()
        .frame(width: 300, height: 400)
        .background(Color.black)
}
