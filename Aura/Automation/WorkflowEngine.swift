import Foundation
import Combine
import AppKit
import UserNotifications

/// Manages workflow execution, scheduling, and persistence
class WorkflowEngine: ObservableObject {
    static let shared = WorkflowEngine()
    
    @Published var workflows: [Workflow] = []
    @Published var isRunningWorkflow: Bool = false
    
    private let contextEngine = ContextEngine.shared
    private let widgetManager = WidgetManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var scheduledTimers: [UUID: Timer] = [:]
    
    private let storageKey = "aura_workflows"
    
    private init() {
        loadWorkflows()
        setupTriggerMonitoring()
    }
    
    // MARK: - Workflow Management
    
    func addWorkflow(_ workflow: Workflow) {
        workflows.append(workflow)
        saveWorkflows()
        setupTrigger(for: workflow)
    }
    
    func removeWorkflow(id: UUID) {
        cancelTrigger(for: id)
        workflows.removeAll { $0.id == id }
        saveWorkflows()
    }
    
    func updateWorkflow(_ workflow: Workflow) {
        if let index = workflows.firstIndex(where: { $0.id == workflow.id }) {
            cancelTrigger(for: workflow.id)
            workflows[index] = workflow
            saveWorkflows()
            setupTrigger(for: workflow)
        }
    }
    
    func toggleWorkflow(id: UUID) {
        if let index = workflows.firstIndex(where: { $0.id == id }) {
            workflows[index].isEnabled.toggle()
            saveWorkflows()
            
            if workflows[index].isEnabled {
                setupTrigger(for: workflows[index])
            } else {
                cancelTrigger(for: id)
            }
        }
    }
    
    // MARK: - Workflow Execution
    
    func runWorkflow(_ workflow: Workflow) {
        guard workflow.isEnabled else { return }
        
        // Check conditions
        let snapshot = createContextSnapshot()
        guard workflow.conditions.allSatisfy({ $0.evaluate(context: snapshot) }) else {
            return
        }
        
        isRunningWorkflow = true
        
        Task {
            for action in workflow.actions {
                await executeAction(action)
            }
            
            await MainActor.run {
                // Update run stats
                if let index = workflows.firstIndex(where: { $0.id == workflow.id }) {
                    workflows[index].lastRun = Date()
                    workflows[index].runCount += 1
                    saveWorkflows()
                }
                isRunningWorkflow = false
            }
        }
    }
    
    func runWorkflowById(_ id: UUID) {
        if let workflow = workflows.first(where: { $0.id == id }) {
            runWorkflow(workflow)
        }
    }
    
    // MARK: - Action Execution
    
    private func executeAction(_ action: WorkflowAction) async {
        switch action {
        case .showWidget(let name):
            await MainActor.run {
                if let widget = widgetManager.widgets.first(where: { $0.name == name }),
                   let index = widgetManager.widgets.firstIndex(where: { $0.id == widget.id }) {
                    widgetManager.widgets[index].isEnabled = true
                }
            }
            
        case .hideWidget(let name):
            await MainActor.run {
                if let widget = widgetManager.widgets.first(where: { $0.name == name }),
                   let index = widgetManager.widgets.firstIndex(where: { $0.id == widget.id }) {
                    widgetManager.widgets[index].isEnabled = false
                }
            }
            
        case .setWidgetPriority(let name, let priority):
            await MainActor.run {
                if let widget = widgetManager.widgets.first(where: { $0.name == name }),
                   let index = widgetManager.widgets.firstIndex(where: { $0.id == widget.id }) {
                    widgetManager.widgets[index].priority = WidgetPriority(rawValue: priority) ?? .normal
                }
            }
            
        case .expandNotch:
            await MainActor.run {
                NotificationCenter.default.post(name: .workflowExpandNotch, object: nil)
            }
            
        case .collapseNotch:
            await MainActor.run {
                NotificationCenter.default.post(name: .workflowCollapseNotch, object: nil)
            }
            
        case .showNotification(let title, let body):
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)
            
        case .runShortcut(let name):
            await MainActor.run {
                let url = URL(string: "shortcuts://run-shortcut?name=\(name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name)")!
                NSWorkspace.shared.open(url)
            }
            
        case .openURL(let urlString):
            await MainActor.run {
                if let url = URL(string: urlString) {
                    NSWorkspace.shared.open(url)
                }
            }
            
        case .openApp(let bundleId):
            await MainActor.run {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                    NSWorkspace.shared.openApplication(at: url, configuration: .init())
                }
            }
            
        case .runAppleScript(let script):
            await MainActor.run {
                if let appleScript = NSAppleScript(source: script) {
                    var error: NSDictionary?
                    appleScript.executeAndReturnError(&error)
                }
            }
            
        case .delay(let seconds):
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    }
    
    // MARK: - Trigger Monitoring
    
    private func setupTriggerMonitoring() {
        // App launch/close
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleAppLaunch(notification)
        }
        
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleAppClose(notification)
        }
        
        // Context changes
        contextEngine.$batteryLevel
            .dropFirst()
            .sink { [weak self] level in
                self?.checkBatteryTriggers(level: level)
            }
            .store(in: &cancellables)
        
        contextEngine.$isCharging
            .dropFirst()
            .sink { [weak self] isCharging in
                self?.checkChargingTriggers(isCharging: isCharging)
            }
            .store(in: &cancellables)
        
        contextEngine.$isFocusMode
            .dropFirst()
            .sink { [weak self] isFocusMode in
                self?.checkFocusTriggers(isFocusMode: isFocusMode)
            }
            .store(in: &cancellables)
        
        contextEngine.$isScreenSharing
            .dropFirst()
            .sink { [weak self] isSharing in
                self?.checkScreenShareTriggers(isSharing: isSharing)
            }
            .store(in: &cancellables)
        
        // Setup time-based triggers
        for workflow in workflows where workflow.isEnabled {
            setupTrigger(for: workflow)
        }
    }
    
    private func setupTrigger(for workflow: Workflow) {
        guard workflow.isEnabled else { return }
        
        if case .timeOfDay(let hour, let minute) = workflow.trigger {
            scheduleTimeBasedTrigger(for: workflow, hour: hour, minute: minute)
        }
    }
    
    private func cancelTrigger(for id: UUID) {
        scheduledTimers[id]?.invalidate()
        scheduledTimers.removeValue(forKey: id)
    }
    
    private func scheduleTimeBasedTrigger(for workflow: Workflow, hour: Int, minute: Int) {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        
        guard let nextTrigger = Calendar.current.nextDate(after: Date(), matching: components, matchingPolicy: .nextTime) else {
            return
        }
        
        let interval = nextTrigger.timeIntervalSinceNow
        
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.runWorkflow(workflow)
            // Reschedule for next day
            self?.scheduleTimeBasedTrigger(for: workflow, hour: hour, minute: minute)
        }
        
        scheduledTimers[workflow.id] = timer
    }
    
    // MARK: - Event Handlers
    
    private func handleAppLaunch(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleId = app.bundleIdentifier else { return }
        
        for workflow in workflows where workflow.isEnabled {
            if case .appLaunched(let triggerBundleId) = workflow.trigger, triggerBundleId == bundleId {
                runWorkflow(workflow)
            }
        }
    }
    
    private func handleAppClose(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleId = app.bundleIdentifier else { return }
        
        for workflow in workflows where workflow.isEnabled {
            if case .appClosed(let triggerBundleId) = workflow.trigger, triggerBundleId == bundleId {
                runWorkflow(workflow)
            }
        }
    }
    
    private func checkBatteryTriggers(level: Int) {
        for workflow in workflows where workflow.isEnabled {
            if case .batteryLevel(let below) = workflow.trigger, level < below {
                runWorkflow(workflow)
            }
        }
    }
    
    private func checkChargingTriggers(isCharging: Bool) {
        for workflow in workflows where workflow.isEnabled {
            if case .batteryCharging(let started) = workflow.trigger, started == isCharging {
                runWorkflow(workflow)
            }
        }
    }
    
    private func checkFocusTriggers(isFocusMode: Bool) {
        for workflow in workflows where workflow.isEnabled {
            if case .focusModeChanged(let active) = workflow.trigger, active == isFocusMode {
                runWorkflow(workflow)
            }
        }
    }
    
    private func checkScreenShareTriggers(isSharing: Bool) {
        for workflow in workflows where workflow.isEnabled {
            if case .screenShareStarted = workflow.trigger, isSharing {
                runWorkflow(workflow)
            }
            if case .screenShareEnded = workflow.trigger, !isSharing {
                runWorkflow(workflow)
            }
        }
    }
    
    // MARK: - Persistence
    
    private func saveWorkflows() {
        if let data = try? JSONEncoder().encode(workflows) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    
    private func loadWorkflows() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([Workflow].self, from: data) {
            workflows = saved
        } else {
            // Load presets on first run
            workflows = Workflow.presets
            saveWorkflows()
        }
    }
    
    // MARK: - Helpers
    
    private func createContextSnapshot() -> ContextSnapshot {
        ContextSnapshot(
            currentApp: contextEngine.currentApp,
            isFocusMode: contextEngine.isFocusMode,
            isInMeeting: contextEngine.isInMeeting,
            batteryLevel: contextEngine.batteryLevel,
            isCharging: contextEngine.isCharging,
            isScreenSharing: contextEngine.isScreenSharing,
            timeOfDay: contextEngine.timeOfDay,
            isWorkHours: contextEngine.isWorkHours
        )
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let workflowExpandNotch = Notification.Name("workflowExpandNotch")
    static let workflowCollapseNotch = Notification.Name("workflowCollapseNotch")
}
