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
///
/// Properties added after `id`, `text` and `dueDate` have default values so SwiftData can
/// add them to existing stores; give any new property a default too.
@Model
final class TodoItem {

    @Attribute(.unique) var id: UUID

    /// The actual description of what needs to be done.
    var text: String

    /// When the task is due.
    var dueDate: Date

    /// `true` once the task has been completed. Completed tasks are hidden from the UI.
    var isCompleted: Bool = false

    /// `true` once the task has been deleted. Soft-deleted tasks are hidden from the UI
    /// but kept in the store (and the backup) so nothing is ever truly lost.
    var isDeleted: Bool = false

    /// `true` if the task is marked urgent — these ring a system alarm (AlarmKit) at
    /// the due time, like Urgent reminders in Apple's Reminders app.
    var isUrgent: Bool = false

    /// How an urgent task's alarm sounds, stored as `AlarmSound.rawValue`. Silent by default.
    var alarmSoundRawValue: String = AlarmSound.silent.rawValue

    /// `true` if the task is an undated "Idea". Ideas have no meaningful due date (the
    /// stored `dueDate` is ignored), get no notifications, and live in the Ideas list.
    /// Setting a due date clears this flag and moves the task back to the Tasks list.
    var isIdea: Bool = false

    init(
        id: UUID = UUID(),
        text: String,
        dueDate: Date,
        isCompleted: Bool = false,
        isDeleted: Bool = false,
        isUrgent: Bool = false,
        alarmSound: AlarmSound = .silent,
        isIdea: Bool = false
    ) {
        self.id = id
        self.text = text
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.isDeleted = isDeleted
        self.isUrgent = isUrgent
        self.alarmSoundRawValue = alarmSound.rawValue
        self.isIdea = isIdea
    }
}

extension TodoItem {

    /// How this task's alarm sounds when it is urgent.
    var alarmSound: AlarmSound {
        get { AlarmSound(rawValue: alarmSoundRawValue) ?? .silent }
        set { alarmSoundRawValue = newValue.rawValue }
    }

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
