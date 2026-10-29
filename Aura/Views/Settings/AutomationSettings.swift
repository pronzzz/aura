import SwiftUI

struct AutomationSettings: View {
    @ObservedObject private var engine = WorkflowEngine.shared
    @State private var editing: Workflow?

    var body: some View {
        Form {
            Section {
                if engine.workflows.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No workflows yet").font(.headline)
                        Text("Workflows run on their own when something happens — your battery drops, an app launches, a meeting is about to start. Start from a template below.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                ForEach(engine.workflows) { workflow in
                    WorkflowRow(workflow: workflow) { editing = workflow }
                }
            } header: {
                HStack {
                    Text("Workflows")
                    Spacer()
                    Menu {
                        Button("Blank Workflow") {
                            editing = Workflow(name: "New Workflow", trigger: WorkflowTrigger(kind: .chargerConnected),
                                               actions: [WorkflowAction(kind: .peek, text: "Hello from Aura")])
                        }
                        Divider()
                        ForEach(Workflow.templates) { template in
                            Button(template.name) {
                                var copy = template
                                copy.id = UUID()
                                copy.actions = copy.actions.map { var action = $0; action.id = UUID(); return action }
                                editing = copy
                            }
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            } footer: {
                Text("Everything runs locally. Workflows can show notifications, peek in the notch, open apps or links, run Shortcuts, start timers, add tasks, control music or run AppleScript.")
            }
        }
        .sheet(item: $editing) { workflow in
            WorkflowEditor(workflow: workflow) { saved in
                if engine.workflows.contains(where: { $0.id == saved.id }) { engine.update(saved) } else { engine.add(saved) }
                editing = nil
            } onCancel: {
                editing = nil
            }
        }
    }
}

private struct WorkflowRow: View {
    let workflow: Workflow
    let edit: () -> Void
    @ObservedObject private var engine = WorkflowEngine.shared

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: workflow.trigger.kind.icon)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.orange.gradient))
            VStack(alignment: .leading, spacing: 2) {
                Text(workflow.name).fontWeight(.medium)
                Text("\(workflow.trigger.summary) → \(workflow.actions.map(\.summary).joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button { engine.run(workflow) } label: { Image(systemName: "play.fill") }
                .buttonStyle(.borderless)
                .help("Run now")
            Button(action: edit) { Image(systemName: "slider.horizontal.3") }
                .buttonStyle(.borderless)
                .help("Edit")
            Toggle("", isOn: Binding(get: { workflow.isEnabled }, set: { engine.setEnabled(workflow.id, $0) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
        .contextMenu {
            Button("Edit…", action: edit)
            Button("Run Now") { engine.run(workflow) }
            Divider()
            Button("Delete", role: .destructive) { engine.remove(workflow.id) }
        }
    }
}

struct WorkflowEditor: View {
    @State var workflow: Workflow
    let onSave: (Workflow) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $workflow.name)
                }
                Section("When") {
                    Picker("Trigger", selection: $workflow.trigger.kind) {
                        ForEach(WorkflowTrigger.Kind.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
                    }
                    switch workflow.trigger.kind {
                    case .batteryBelow:
                        Stepper("Below \(workflow.trigger.number)%", value: $workflow.trigger.number, in: 5...95, step: 5)
                    case .appLaunched, .appQuit:
                        TextField("App name or bundle ID", text: $workflow.trigger.text, prompt: Text("e.g. Xcode"))
                    case .timeOfDay:
                        HStack {
                            Stepper("Hour \(workflow.trigger.hour)", value: $workflow.trigger.hour, in: 0...23)
                            Stepper(String(format: "Minute %02d", workflow.trigger.minute), value: $workflow.trigger.minute, in: 0...59, step: 5)
                        }
                    case .meetingSoon:
                        Stepper("\(workflow.trigger.number) min before", value: $workflow.trigger.number, in: 1...60)
                    default:
                        EmptyView()
                    }
                }
                Section {
                    ForEach($workflow.actions) { $action in
                        ActionEditor(action: $action) {
                            workflow.actions.removeAll { $0.id == action.id }
                        }
                    }
                } header: {
                    HStack {
                        Text("Do")
                        Spacer()
                        Menu {
                            ForEach(WorkflowAction.Kind.allCases) { kind in
                                Button { workflow.actions.append(WorkflowAction(kind: kind)) } label: {
                                    Label(kind.title, systemImage: kind.icon)
                                }
                            }
                        } label: {
                            Label("Add Action", systemImage: "plus")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
                Button("Save") { onSave(workflow) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(workflow.name.trimmingCharacters(in: .whitespaces).isEmpty || workflow.actions.isEmpty)
            }
            .padding(12)
        }
        .frame(width: 520, height: 520)
    }
}

private struct ActionEditor: View {
    @Binding var action: WorkflowAction
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("", selection: $action.kind) {
                    ForEach(WorkflowAction.Kind.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
                }
                .labelsHidden()
                Spacer()
                Button(role: .destructive, action: remove) { Image(systemName: "minus.circle.fill") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
            }
            if action.kind == .startTimer {
                Stepper("\(action.number) minutes", value: $action.number, in: 1...240)
            }
            if let label = action.kind.textLabel {
                if action.kind == .appleScript {
                    TextEditor(text: $action.text)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 70)
                } else {
                    TextField(label, text: $action.text)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
