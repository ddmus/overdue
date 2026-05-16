//
//  TodoItem.swift
//  overdo
//
//  Created by tomas on 16.05.2026.
//

import Foundation

/// A single task. Named `TodoItem` to avoid colliding with Swift Concurrency's `Task`.
struct TodoItem: Identifiable, Hashable {

    let id: UUID

    /// The actual description of what needs to be done.
    var text: String

    /// When the task is due.
    var dueDate: Date

    /// `true` once the task has been completed. Completed tasks are hidden from the UI.
    var isCompleted: Bool

    init(id: UUID = UUID(), text: String, dueDate: Date, isCompleted: Bool = false) {
        self.id = id
        self.text = text
        self.dueDate = dueDate
        self.isCompleted = isCompleted
    }
}

extension TodoItem {

    /// `true` when the due date is in the past.
    func isOverdue(at reference: Date = .now) -> Bool {
        dueDate < reference
    }

    /// Calculated UI field, e.g. "in 18 min" for a future task or "18 min ago" for a past one.
    func relativeText(at reference: Date = .now) -> String {
        let interval = dueDate.timeIntervalSince(reference)
        let isPast = interval < 0
        let seconds = Int(abs(interval).rounded())

        let value: Int
        let unit: String
        switch seconds {
        case ..<60:
            value = seconds
            unit = "sec"
        case ..<3_600:
            value = seconds / 60
            unit = "min"
        case ..<86_400:
            value = seconds / 3_600
            unit = "hr"
        default:
            value = seconds / 86_400
            unit = "day"
        }

        return isPast ? "\(value) \(unit) ago" : "in \(value) \(unit)"
    }
}
