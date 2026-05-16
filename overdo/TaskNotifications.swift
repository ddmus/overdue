//
//  TaskNotifications.swift
//  overdo
//
//  Created by tomas on 16.05.2026.
//

import Foundation
import UserNotifications

/// Schedules and cancels the local notification that reminds the user when a task is due.
/// Each task's `id` doubles as its notification request identifier, so rescheduling
/// simply replaces the previous request.
enum TaskNotifications {

    static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Schedules (or reschedules) the due reminder for a task.
    /// Completed or already-overdue tasks have any pending reminder removed instead.
    static func schedule(for task: TodoItem) {
        let center = UNUserNotificationCenter.current()
        let identifier = task.id.uuidString

        guard !task.isCompleted, task.dueDate > .now else {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Task due"
        content.body = task.text
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: task.dueDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        // Adding a request with an existing identifier replaces the previous one.
        center.add(request)
    }

    static func cancel(for task: TodoItem) {
        cancel(id: task.id)
    }

    static func cancel(id: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [id.uuidString])
    }
}
