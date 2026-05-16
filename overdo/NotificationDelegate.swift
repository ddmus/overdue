//
//  NotificationDelegate.swift
//  overdo
//
//  Created by tomas on 16.05.2026.
//

import SwiftData
import UserNotifications

/// Handles due reminders: shows them while the app is in the foreground and
/// applies the postpone actions chosen from the notification's context menu.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        super.init()
    }

    /// Lets a due reminder appear as a banner even while the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    /// Applies a postpone action picked from the notification.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard
            let action = TaskNotifications.Action(rawValue: response.actionIdentifier),
            let taskID = UUID(uuidString: response.notification.request.identifier)
        else {
            return
        }
        postpone(taskID: taskID, by: action.interval)
    }

    private func postpone(taskID: UUID, by interval: TimeInterval) {
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<TodoItem>(
            predicate: #Predicate<TodoItem> { $0.id == taskID }
        )

        guard let task = try? context.fetch(descriptor).first else { return }

        task.dueDate = .now.addingTimeInterval(interval)
        try? context.save()

        // Resync all reminders so badge counts stay correct.
        let allTasks = (try? context.fetch(FetchDescriptor<TodoItem>())) ?? []
        TaskNotifications.sync(tasks: allTasks)
    }
}
