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
/// Reminders are managed as a whole via `sync(tasks:)`: every change reschedules
/// the full set so each notification can carry the correct app-icon badge value
/// for the moment it fires — which keeps the badge accurate even while the app is
/// backgrounded or terminated.
enum TaskNotifications {

    /// Notification category that carries the postpone actions.
    static let categoryIdentifier = "TASK_DUE"

    /// iOS only keeps the 64 soonest pending local notifications per app.
    private static let pendingLimit = 64

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

    /// Reschedules every reminder from the current task set.
    ///
    /// Each notification's badge is the number of tasks that will be overdue once it
    /// fires: the tasks already overdue now, plus every task due no later than this one.
    static func sync(tasks: [TodoItem]) {
        let center = UNUserNotificationCenter.current()
        let now = Date.now

        let active = tasks.filter { !$0.isCompleted }
        let alreadyOverdueCount = active.filter { $0.dueDate <= now }.count
        let upcoming = active
            .filter { $0.dueDate > now }
            .sorted { $0.dueDate < $1.dueDate }
            .prefix(pendingLimit)

        // Drop reminders for tasks that no longer need one (completed, deleted, overdue).
        let keepIDs = Set(upcoming.map { $0.id.uuidString })
        center.getPendingNotificationRequests { requests in
            let staleIDs = requests.map(\.identifier).filter { !keepIDs.contains($0) }
            if !staleIDs.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: staleIDs)
            }
        }

        // If a task is upcoming again, clear any reminder that already fired and is
        // still sitting in Notification Center from when the task was overdue.
        center.removeDeliveredNotifications(withIdentifiers: Array(keepIDs))

        // (Re)schedule each upcoming reminder with its cumulative badge count.
        for (index, task) in upcoming.enumerated() {
            schedule(task, badge: alreadyOverdueCount + index + 1, center: center)
        }
    }

    /// Fully clears a task's reminder — both the scheduled request and any
    /// already-delivered notification. Use when a task is completed or deleted.
    static func cancel(taskID: UUID) {
        let center = UNUserNotificationCenter.current()
        let ids = [taskID.uuidString]
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    private static func schedule(_ task: TodoItem, badge: Int, center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.title = "Task due"
        content.body = task.text
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        content.badge = NSNumber(value: badge)

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: task.dueDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        // Adding a request with an existing identifier replaces the previous one.
        let request = UNNotificationRequest(
            identifier: task.id.uuidString,
            content: content,
            trigger: trigger
        )
        center.add(request)
    }
}
