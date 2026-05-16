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

    /// Actions offered in the notification's context menu, in display order.
    enum Action: String, CaseIterable {
        case markDone = "MARK_DONE"
        case postpone15m = "POSTPONE_15M"
        case postpone1h = "POSTPONE_1H"
        case postpone1d = "POSTPONE_1D"

        var title: String {
            switch self {
            case .markDone: "Mark done"
            case .postpone15m: "Postpone 15 min"
            case .postpone1h: "Postpone 1 hour"
            case .postpone1d: "Postpone 1 day"
            }
        }

        var iconName: String {
            switch self {
            case .markDone: "checkmark"
            case .postpone15m, .postpone1h, .postpone1d: "clock"
            }
        }

        /// How far into the future the task is pushed; `nil` for non-postpone actions.
        var postponeInterval: TimeInterval? {
            switch self {
            case .markDone: nil
            case .postpone15m: 15 * 60
            case .postpone1h: 60 * 60
            case .postpone1d: 24 * 60 * 60
            }
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
