//
//  TaskNotifications.swift
//  overdo
//
//  Created by tomas on 16.05.2026.
//

import Foundation
import UserNotifications

/// Schedules the local reminders for tasks.
///
/// Each task gets a single reminder at its due date. Urgent tasks additionally ring
/// an alarm (see `TaskAlarms`), so their reminder is silent — it only keeps the task
/// in Notification Center with its postpone actions and badge.
enum TaskNotifications {

    /// Notification category that carries the postpone actions.
    static let categoryIdentifier = "TASK_DUE"

    /// iOS keeps at most this many pending local notifications per app.
    private static let pendingLimit = 64

    /// Actions offered in the notification and in-app context menus, in display order.
    enum Action: String, CaseIterable {
        case markDone = "MARK_DONE"
        case postpone15m = "POSTPONE_15M"
        case postpone1h = "POSTPONE_1H"
        case postpone3h = "POSTPONE_3H"
        case postpone1d = "POSTPONE_1D"
        case at7 = "AT_07_00"
        case at9 = "AT_09_00"
        case at12 = "AT_12_00"
        case at18 = "AT_18_00"
        case at20 = "AT_20_00"

        /// Menu grouping; the in-app context menu shows a divider between groups.
        enum Group: CaseIterable {
            case complete, postpone, schedule
        }

        var group: Group {
            switch self {
            case .markDone: .complete
            case .postpone15m, .postpone1h, .postpone3h, .postpone1d: .postpone
            case .at7, .at9, .at12, .at18, .at20: .schedule
            }
        }

        var title: String {
            switch self {
            case .markDone: "Mark done"
            case .postpone15m: "Postpone 15 min"
            case .postpone1h: "Postpone 1 hour"
            case .postpone3h: "Postpone 3 hours"
            case .postpone1d: "Postpone 1 day"
            case .at7: "7:00"
            case .at9: "9:00"
            case .at12: "12:00"
            case .at18: "18:00"
            case .at20: "20:00"
            }
        }

        var iconName: String {
            switch self {
            case .markDone: "checkmark"
            case .postpone15m, .postpone1h, .postpone3h, .postpone1d: "clock"
            case .at7, .at9, .at12, .at18, .at20: "alarm"
            }
        }

        /// The new due date this action produces, or `nil` for `markDone`.
        func resolvedDueDate(from now: Date = .now) -> Date? {
            switch self {
            case .markDone:
                return nil
            case .postpone15m:
                return now.addingTimeInterval(15 * 60)
            case .postpone1h:
                return now.addingTimeInterval(60 * 60)
            case .postpone3h:
                return now.addingTimeInterval(3 * 60 * 60)
            case .postpone1d:
                return now.addingTimeInterval(24 * 60 * 60)
            case .at7:
                return Self.nextOccurrence(ofHour: 7, from: now)
            case .at9:
                return Self.nextOccurrence(ofHour: 9, from: now)
            case .at12:
                return Self.nextOccurrence(ofHour: 12, from: now)
            case .at18:
                return Self.nextOccurrence(ofHour: 18, from: now)
            case .at20:
                return Self.nextOccurrence(ofHour: 20, from: now)
            }
        }

        /// The next time the clock reads `hour:00` — today if still ahead, else tomorrow.
        private static func nextOccurrence(ofHour hour: Int, from now: Date) -> Date {
            let calendar = Calendar.current
            if let todayAtHour = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now),
               todayAtHour > now {
                return todayAtHour
            }
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        }
    }

    static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Registers the postpone actions. Must run before any reminder is delivered.
    static func registerCategories() {
        let actions = Action.allCases.map { action in
            UNNotificationAction(
                identifier: action.rawValue,
                title: action.title,
                options: [],
                icon: UNNotificationActionIcon(systemImageName: action.iconName)
            )
        }
        let category = UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: actions,
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: - Identifiers

    /// A reminder identifier looks like `<taskID>#0`. The `#<slot>` suffix is left over
    /// from repeating reminders and kept so older delivered ones still map to their task.
    private static func makeIdentifier(taskID: UUID) -> String {
        "\(taskID.uuidString)#0"
    }

    private static func isIdentifier(_ identifier: String, forTaskID taskID: UUID) -> Bool {
        identifier.hasPrefix("\(taskID.uuidString)#")
    }

    /// Extracts the task id from a reminder identifier — used to map a tapped
    /// notification back to its task.
    static func taskID(fromIdentifier identifier: String) -> UUID? {
        UUID(uuidString: identifier.components(separatedBy: "#").first ?? "")
    }

    // MARK: - Scheduling

    /// Reschedules every reminder (and every urgent task's alarm) from the current task set.
    ///
    /// Reminders that have already fired stay in Notification Center; only future
    /// ones are (re)scheduled. The soonest reminders win the limited pending budget.
    static func sync(tasks: [TodoItem]) {
        let center = UNUserNotificationCenter.current()
        let now = Date.now
        let active = tasks.filter { !$0.isCompleted && !$0.isDeleted && !$0.isIdea }

        TaskAlarms.sync(tasks: active)

        let upcoming = active.filter { $0.dueDate > now }
        let reminders = upcoming.map { task in
            PlannedReminder(
                identifier: makeIdentifier(taskID: task.id),
                fireDate: task.dueDate,
                body: task.text,
                badge: active.filter { $0.dueDate <= task.dueDate }.count,
                // An urgent task's alarm makes the sound.
                isSilent: task.isUrgent
            )
        }

        // Honour the global pending limit: keep the soonest reminders.
        let scheduled = reminders.sorted { $0.fireDate < $1.fireDate }.prefix(pendingLimit)
        let keepIDs = Set(scheduled.map(\.identifier))

        Task {
            let staleIDs = await center.pendingNotificationRequests()
                .map(\.identifier)
                .filter { !keepIDs.contains($0) }
            if !staleIDs.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: staleIDs)
            }
            for reminder in scheduled {
                try? await center.add(reminder.request())
            }
        }

        // A task that is upcoming again should not keep reminders that already fired
        // while it was overdue.
        let upcomingTaskIDs = upcoming.map(\.id)
        if !upcomingTaskIDs.isEmpty {
            Task {
                let toRemove = await center.deliveredNotifications()
                    .map(\.request.identifier)
                    .filter { id in upcomingTaskIDs.contains { isIdentifier(id, forTaskID: $0) } }
                if !toRemove.isEmpty {
                    center.removeDeliveredNotifications(withIdentifiers: toRemove)
                }
            }
        }
    }

    /// Fully clears a task's reminders — every pending request, every already-delivered
    /// notification and its alarm. Use when a task is completed or deleted.
    static func cancel(taskID: UUID) {
        TaskAlarms.cancel(taskID: taskID)
        let center = UNUserNotificationCenter.current()
        Task {
            let ids = await center.pendingNotificationRequests()
                .map(\.identifier)
                .filter { isIdentifier($0, forTaskID: taskID) }
            if !ids.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: ids)
            }
        }
        clearDelivered(taskID: taskID)
    }

    /// Removes a task's already-delivered reminders from Notification Center, leaving
    /// pending ones to `sync`. Use after the task is edited, so stale text or times
    /// don't linger; if it is still overdue, `sync` schedules a fresh reminder.
    static func clearDelivered(taskID: UUID) {
        let center = UNUserNotificationCenter.current()
        Task {
            let ids = await center.deliveredNotifications()
                .map(\.request.identifier)
                .filter { isIdentifier($0, forTaskID: taskID) }
            if !ids.isEmpty {
                center.removeDeliveredNotifications(withIdentifiers: ids)
            }
        }
    }

    /// One task's reminder, ready to be turned into a request.
    private struct PlannedReminder {
        let identifier: String
        let fireDate: Date
        let body: String
        let badge: Int
        let isSilent: Bool

        func request() -> UNNotificationRequest {
            let content = UNMutableNotificationContent()
            content.body = body
            content.sound = isSilent ? nil : .default
            content.categoryIdentifier = TaskNotifications.categoryIdentifier
            content.badge = NSNumber(value: badge)

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        }
    }
}
