//
//  BulkEditSheet.swift
//  overdo
//
//  Created by tomas on 16.05.2026.
//

import SwiftUI

/// Taller bottom sheet for editing several tasks at once. The tasks are listed
/// read-only; the user can either set a shared due date or turn them all into Ideas.
struct BulkEditSheet: View {

    /// The outcome the user chose for the selected tasks.
    enum Result {
        /// Apply this due date to every task (and clear their Idea flag).
        case setDueDate(Date)
        /// Turn every task into an undated Idea.
        case makeIdea
    }

    let tasks: [TodoItem]
    let onSave: (Result) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var dueDate: Date = .now.addingTimeInterval(3_600)
    @State private var makeIdea = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(tasks) { task in
                        Text(task.text)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("^[\(tasks.count) task](inflect: true)")
                }

                Section {
                    Toggle(isOn: $makeIdea) {
                        Label("Idea", systemImage: "lightbulb")
                    }
                } footer: {
                    Text("Turn these into undated ideas, removing their due date.")
                }

                // Date controls only apply when not converting to ideas.
                if !makeIdea {
                    DueDateSection(dueDate: $dueDate)
                }
            }
            .navigationTitle(makeIdea ? "Make Ideas" : "Edit Due Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(makeIdea ? .makeIdea : .setDueDate(dueDate))
                        dismiss()
                    }
                    .disabled(tasks.isEmpty)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemGroupedBackground))
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            BulkEditSheet(
                tasks: [
                    TodoItem(text: "Call the dentist", dueDate: .now),
                    TodoItem(text: "Submit the report", dueDate: .now),
                    TodoItem(text: "Water the plants", dueDate: .now)
                ],
                onSave: { _ in }
            )
        }
}
