//
//  BulkEditSheet.swift
//  overdo
//
//  Created by tomas on 16.05.2026.
//

import SwiftUI

/// Taller bottom sheet for editing the due date/time of several tasks at once.
/// The tasks are listed read-only; only the shared due date is editable.
struct BulkEditSheet: View {

    let tasks: [TodoItem]
    /// Called with the new due date to apply to every task.
    let onSave: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var dueDate: Date = .now.addingTimeInterval(3_600)

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

                DueDateSection(dueDate: $dueDate)
            }
            .navigationTitle("Edit Due Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(dueDate)
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
