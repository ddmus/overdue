//
//  TaskSheet.swift
//  overdo
//
//  Created by tomas on 16.05.2026.
//

import SwiftUI

/// Bottom sheet for creating a new task or editing an existing one.
struct TaskSheet: View {

    enum Mode {
        /// Creating a brand new task. `isIdea` seeds the Idea toggle (on from the Ideas tab).
        case create(isIdea: Bool)
        /// Editing an existing task.
        case edit(TodoItem)
    }

    /// The values entered in the sheet, passed back on add/save.
    struct Result {
        var text: String
        var dueDate: Date
        var isUrgent: Bool
        var isIdea: Bool
    }

    let mode: Mode
    /// Called with the entered values when the user adds or saves.
    let onSubmit: (Result) -> Void
    /// Called when the user completes an existing task. Unused in `.create` mode.
    var onComplete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var text: String
    @State private var dueDate: Date
    @State private var isUrgent: Bool
    @State private var isIdea: Bool
    @FocusState private var isTextFieldFocused: Bool

    init(
        mode: Mode,
        onSubmit: @escaping (Result) -> Void,
        onComplete: (() -> Void)? = nil
    ) {
        self.mode = mode
        self.onSubmit = onSubmit
        self.onComplete = onComplete

        switch mode {
        case .create(let isIdea):
            _text = State(initialValue: "")
            _dueDate = State(initialValue: .now.addingTimeInterval(3_600))
            _isUrgent = State(initialValue: false)
            _isIdea = State(initialValue: isIdea)
        case .edit(let task):
            _text = State(initialValue: task.text)
            _dueDate = State(initialValue: task.dueDate)
            _isUrgent = State(initialValue: task.isUrgent)
            _isIdea = State(initialValue: task.isIdea)
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Performs the default action — Add (create) or Save (edit) — then dismisses.
    /// An optional `date` overrides the picked due date (used by Quick save).
    private func submit(date: Date? = nil) {
        guard !trimmedText.isEmpty else { return }
        onSubmit(Result(
            text: trimmedText,
            dueDate: date ?? dueDate,
            // An idea has no due date, so it can't be urgent.
            isUrgent: isIdea ? false : isUrgent,
            isIdea: isIdea
        ))
        dismiss()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What needs to be done?", text: $text, axis: .vertical)
                        .lineLimit(1...8)
                        .focused($isTextFieldFocused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.sentences)
                }

                Section {
                    Toggle(isOn: $isUrgent) {
                        Label("Urgent", systemImage: "alarm.waves.left.and.right.fill")
                    }
                    .disabled(isIdea)
                    .onChange(of: isUrgent) { _, newValue in
                        // Ask for alarm permission the first time a task is made urgent.
                        if newValue { Task { await TaskAlarms.requestAuthorization() } }
                    }

                    Toggle(isOn: $isIdea) {
                        Label("Idea", systemImage: "lightbulb")
                    }
                } footer: {
                    Text(isIdea
                        ? "An idea has no due date and gets no reminders. Set a due date to schedule it."
                        : "Urgent rings an alarm at the due time, even in Silent mode or Focus.")
                }
                .onChange(of: isIdea) { _, newValue in
                    // An idea can't be urgent — it has no due date.
                    if newValue { isUrgent = false }
                }

                // Date controls only make sense for scheduled (non-idea) tasks.
                if !isIdea {
                    DueDateSection(dueDate: $dueDate)

                    QuickSaveSection(
                        onQuickSave: { date in submit(date: date) },
                        isDisabled: trimmedText.isEmpty
                    )
                }

                if isEditing {
                    Section {
                        Button {
                            onComplete?()
                            dismiss()
                        } label: {
                            Label("Complete", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .tint(.green)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Task" : "New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") {
                        submit()
                    }
                    .disabled(trimmedText.isEmpty)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemGroupedBackground))
        .onAppear {
            // Auto-focus the text field only when creating a new task.
            if !isEditing { isTextFieldFocused = true }
        }
    }
}

#Preview("Create") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            TaskSheet(mode: .create(isIdea: false)) { _ in }
        }
}

#Preview("Edit") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            TaskSheet(
                mode: .edit(TodoItem(text: "Call the dentist", dueDate: .now)),
                onSubmit: { _ in },
                onComplete: {}
            )
        }
}
