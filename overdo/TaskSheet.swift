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
    /// Called with the entered text and chosen due date when the user adds or saves.
    let onSubmit: (String, Date) -> Void
    /// Called when the user completes an existing task. Unused in `.create` mode.
    var onComplete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var text: String
    @State private var dueDate: Date
    @FocusState private var isTextFieldFocused: Bool

    init(
        mode: Mode,
        onSubmit: @escaping (String, Date) -> Void,
        onComplete: (() -> Void)? = nil
    ) {
        self.mode = mode
        self.onSubmit = onSubmit
        self.onComplete = onComplete

        switch mode {
        case .create:
            _text = State(initialValue: "")
            _dueDate = State(initialValue: .now.addingTimeInterval(3_600))
        case .edit(let task):
            _text = State(initialValue: task.text)
            _dueDate = State(initialValue: task.dueDate)
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
    private func submit() {
        guard !trimmedText.isEmpty else { return }
        onSubmit(trimmedText, dueDate)
        dismiss()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What needs to be done?", text: $text)
                        .focused($isTextFieldFocused)
                        .submitLabel(.done)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.sentences)
                        .onSubmit { submit() }
                }

                DueDateSection(dueDate: $dueDate)

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
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            // Auto-focus the text field only when creating a new task.
            if !isEditing { isTextFieldFocused = true }
        }
    }
}

#Preview("Create") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            TaskSheet(mode: .create) { _, _ in }
        }
}

#Preview("Edit") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            TaskSheet(
                mode: .edit(TodoItem(text: "Call the dentist", dueDate: .now)),
                onSubmit: { _, _ in },
                onComplete: {}
            )
        }
}
