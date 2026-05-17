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
/// Each task gets a *series* of one-shot reminders, pre-scheduled `repeatInterval`
/// apart: one at the due date, then one every few minutes after. Because they are
/// scheduled upfront, they keep firing even if the app is never opened. They use
/// distinct identifiers (`<taskID>#<slot>`), so they appear as separate, stacked
/// notifications rather than collapsing into one.
enum TaskNotifications {

    /// Notification category that carries the postpone actions.
    static let categoryIdentifier = "TASK_DUE"

    /// iOS keeps at most this many pending local notifications per app.
    private static let pendingLimit = 64

    /// Spacing between the reminders in a task's series.
    private static let repeatInterval: TimeInterval = 5 * 60

    /// How many reminders are pre-scheduled per task on each sync — covers
    /// `perTaskSeriesLength * repeatInterval` of nagging, refreshed whenever the app runs.
    private static let perTaskSeriesLength = 24

    /// Actions offered in the notification and in-app context menus, in display order.
    enum Action: String, CaseIterable {
        case markDone = "MARK_DONE"
        case postpone15m = "POSTPONE_15M"
        case postpone1h = "POSTPONE_1H"
        case postpone1d = "POSTPONE_1D"
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
            case .postpone15m, .postpone1h, .postpone1d: .postpone
            case .at9, .at12, .at18, .at20: .schedule
            }
        }

        var title: String {
            switch self {
            case .markDone: "Mark done"
            case .postpone15m: "Postpone 15 min"
            case .postpone1h: "Postpone 1 hour"
            case .postpone1d: "Postpone 1 day"
            case .at9: "9:00"
            case .at12: "12:00"
            case .at18: "18:00"
            case .at20: "20:00"
            }
        }

        var iconName: String {
            switch self {
            case .markDone: "checkmark"
            case .postpone15m, .postpone1h, .postpone1d: "clock"
            case .at9, .at12, .at18, .at20: "alarm"
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
            case .postpone1d:
                return now.addingTimeInterval(24 * 60 * 60)
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

    /// A reminder identifier looks like `<taskID>#<slot>`.
    private static func makeIdentifier(taskID: UUID, slot: Int) -> String {
        "\(taskID.uuidString)#\(slot)"
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

    /// Reschedules every reminder series from the current task set.
    ///
    /// Each task contributes a series of reminders (due date, +5 min, +10 min, …).
    /// Reminders that have already fired stay in Notification Center; only future
    /// ones are (re)scheduled. The soonest reminders win the limited pending budget.
    static func sync(tasks: [TodoItem]) {
        let center = UNUserNotificationCenter.current()
        let now = Date.now
        let active = tasks.filter { !$0.isCompleted }

        // Build every future reminder slot across all tasks.
        var slots: [PlannedReminder] = []
        for task in active {
            let elapsed = now.timeIntervalSince(task.dueDate)
            let firstSlot = elapsed <= 0 ? 0 : Int(elapsed / repeatInterval) + 1

            for slot in firstSlot ..< (firstSlot + perTaskSeriesLength) {
                let fireDate = task.dueDate.addingTimeInterval(repeatInterval * Double(slot))
                guard fireDate > now else { continue }

                slots.append(PlannedReminder(
                    identifier: makeIdentifier(taskID: task.id, slot: slot),
                    fireDate: fireDate,
                    // First reminder shows just the task text; repeats add an "Overdue" title.
                    title: slot == 0 ? "" : "Overdue",
                    body: task.text,
                    badge: active.filter { $0.dueDate <= fireDate }.count
                ))
            }
        }

        // Honour the global pending limit: keep the soonest reminders.
        let scheduled = slots.sorted { $0.fireDate < $1.fireDate }.prefix(pendingLimit)
        let keepIDs = Set(scheduled.map(\.identifier))

        center.getPendingNotificationRequests { requests in
            let staleIDs = requests.map(\.identifier).filter { !keepIDs.contains($0) }
            if !staleIDs.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: staleIDs)
            }
            for reminder in scheduled {
                center.add(reminder.request())
            }
        }

        // A task that is upcoming again should not keep reminders that already fired
        // while it was overdue.
        let upcomingTaskIDs = active.filter { $0.dueDate > now }.map(\.id)
        if !upcomingTaskIDs.isEmpty {
            center.getDeliveredNotifications { delivered in
                let toRemove = delivered.map(\.request.identifier).filter { id in
                    upcomingTaskIDs.contains { isIdentifier(id, forTaskID: $0) }
                }
                if !toRemove.isEmpty {
                    center.removeDeliveredNotifications(withIdentifiers: toRemove)
                }
            }
        }
    }

    /// Fully clears a task's reminder series — every pending request and every
    /// already-delivered notification. Use when a task is completed or deleted.
    static func cancel(taskID: UUID) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { isIdentifier($0, forTaskID: taskID) }
            if !ids.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: ids)
            }
        }
        center.getDeliveredNotifications { delivered in
            let ids = delivered.map(\.request.identifier).filter { isIdentifier($0, forTaskID: taskID) }
            if !ids.isEmpty {
                center.removeDeliveredNotifications(withIdentifiers: ids)
            }
        }
    }

    /// One reminder in a task's series, ready to be turned into a request.
    private struct PlannedReminder {
        let identifier: String
        let fireDate: Date
        let title: String
        let body: String
        let badge: Int

        func request() -> UNNotificationRequest {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
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
