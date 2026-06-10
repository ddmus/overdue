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
        /// Creating a brand new task. Due date defaults to one hour from now.
        case create
        /// Editing an existing task.
        case edit(TodoItem)
    }

    let mode: Mode
    /// Called with the entered text, chosen due date, and time-sensitive flag when the
    /// user adds or saves.
    let onSubmit: (String, Date, Bool) -> Void
    /// Called when the user completes an existing task. Unused in `.create` mode.
    var onComplete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var text: String
    @State private var dueDate: Date
    @State private var isTimeSensitive: Bool
    @FocusState private var isTextFieldFocused: Bool

    init(
        mode: Mode,
        onSubmit: @escaping (String, Date, Bool) -> Void,
        onComplete: (() -> Void)? = nil
    ) {
        self.mode = mode
        self.onSubmit = onSubmit
        self.onComplete = onComplete

        switch mode {
        case .create:
            _text = State(initialValue: "")
            _dueDate = State(initialValue: .now.addingTimeInterval(3_600))
            _isTimeSensitive = State(initialValue: false)
        case .edit(let task):
            _text = State(initialValue: task.text)
            _dueDate = State(initialValue: task.dueDate)
            _isTimeSensitive = State(initialValue: task.isTimeSensitive)
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
        onSubmit(trimmedText, date ?? dueDate, isTimeSensitive)
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
                    Toggle(isOn: $isTimeSensitive) {
                        Label("Time Sensitive", systemImage: "bell.badge.fill")
                    }
                } footer: {
                    Text("Keep reminding me every 5 minutes while this task is overdue.")
                }

                DueDateSection(dueDate: $dueDate)

                QuickSaveSection(
                    onQuickSave: { date in submit(date: date) },
                    isDisabled: trimmedText.isEmpty
                )

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
            TaskSheet(mode: .create) { _, _, _ in }
        }
}

#Preview("Edit") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            TaskSheet(
                mode: .edit(TodoItem(text: "Call the dentist", dueDate: .now)),
                onSubmit: { _, _, _ in },
                onComplete: {}
            )
        }
}
