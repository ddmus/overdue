//
//  TodoItem.swift
//  overdo
//
//  Created by tomas on 16.05.2026.
//

import Foundation
import SwiftData

/// A single task, persisted with SwiftData.
/// Named `TodoItem` to avoid colliding with Swift Concurrency's `Task`.
@Model
final class TodoItem {

    @Attribute(.unique) var id: UUID

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

    /// The due time only, e.g. "20:00".
    func dueTimeText() -> String {
        dueDate.formatted(.dateTime.hour().minute())
    }

    /// The due time prefixed with its day, e.g. "Tomorrow 20:00" or "Friday 15:00".
    /// More than a week away it uses the date instead, e.g. "15-June, 08:00".
    func dueDayTimeText(at now: Date = .now) -> String {
        let calendar = Calendar.current
        let time = dueTimeText()
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: dueDate)
        ).day ?? 0

        switch days {
        case 1:
            return "Tomorrow \(time)"
        case 2...6:
            return "\(dueDate.formatted(.dateTime.weekday(.wide))) \(time)"
        case 7...:
            return "\(Self.dayMonthFormatter.string(from: dueDate)), \(time)"
        default:
            return time
        }
    }

    private static let dayMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d-MMMM"
        return formatter
    }()

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
