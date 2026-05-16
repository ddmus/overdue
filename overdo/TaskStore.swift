//
//  TaskStore.swift
//  overdo
//
//  Created by tomas on 16.05.2026.
//

import Foundation
import Observation

/// Holds the list of tasks, kept sorted by due date (soonest first).
@Observable
final class TaskStore {

    private(set) var tasks: [TodoItem] = []

    /// Tasks shown in the UI: everything that has not been completed.
    var activeTasks: [TodoItem] {
        tasks.filter { !$0.isCompleted }
    }

    func add(text: String, dueDate: Date) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        tasks.append(TodoItem(text: trimmed, dueDate: dueDate))
        sort()
    }

    /// Applies edits made to an existing task.
    func update(_ task: TodoItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index] = task
        sort()
    }

    func complete(_ task: TodoItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].isCompleted = true
    }

    func delete(_ task: TodoItem) {
        tasks.removeAll { $0.id == task.id }
    }

    private func sort() {
        tasks.sort { $0.dueDate < $1.dueDate }
    }
}
