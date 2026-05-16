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

    /// Applies an action picked from the notification's context menu.
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

        switch action {
        case .markDone:
            complete(taskID: taskID)
        case .postpone15m, .postpone1h, .postpone1d:
            if let interval = action.postponeInterval {
                postpone(taskID: taskID, by: interval)
            }
        }
    }

    private func complete(taskID: UUID) {
        let context = modelContainer.mainContext
        guard let task = task(with: taskID, in: context) else { return }

        task.isCompleted = true
        try? context.save()

        // Remove the fired notification, then resync so badge counts stay correct.
        TaskNotifications.cancel(taskID: taskID)
        resyncReminders(context: context)
    }

    private func postpone(taskID: UUID, by interval: TimeInterval) {
        let context = modelContainer.mainContext
        guard let task = task(with: taskID, in: context) else { return }

        task.dueDate = .now.addingTimeInterval(interval)
        try? context.save()

        resyncReminders(context: context)
    }

    private func task(with id: UUID, in context: ModelContext) -> TodoItem? {
        let descriptor = FetchDescriptor<TodoItem>(
            predicate: #Predicate<TodoItem> { $0.id == id }
        )
        return try? context.fetch(descriptor).first
    }

    /// Reschedules all reminders so the badge counts stay correct.
    private func resyncReminders(context: ModelContext) {
        let allTasks = (try? context.fetch(FetchDescriptor<TodoItem>())) ?? []
        TaskNotifications.sync(tasks: allTasks)
    }
}
