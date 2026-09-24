//
//  NotificationDelegate.swift
//  overdo
//
//  Created by tomas on 16.05.2026.
//

import Observation
import SwiftData
import UserNotifications

/// Carries the task whose notification was tapped to the UI, which opens its detail.
@Observable
final class NotificationRouter {
    /// Set when a reminder is tapped; the UI clears it once the task sheet is shown.
    var taskIDToOpen: UUID?
}

/// Handles due reminders: shows them while the app is in the foreground and
/// applies the postpone actions chosen from the notification's context menu.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    private let modelContainer: ModelContainer
    private let router: NotificationRouter

    init(modelContainer: ModelContainer, router: NotificationRouter) {
        self.modelContainer = modelContainer
        self.router = router
        super.init()
    }

    /// Lets a due reminder appear as a banner even while the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    /// Opens the task when the notification itself is tapped, or applies an action
    /// picked from its context menu.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let taskID = TaskNotifications.taskID(fromIdentifier: response.notification.request.identifier) else {
            return
        }

        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            router.taskIDToOpen = taskID
            return
        }

        guard let action = TaskNotifications.Action(rawValue: response.actionIdentifier) else {
            return
        }

        switch action {
        case .markDone:
            complete(taskID: taskID)
        default:
            if let newDueDate = action.resolvedDueDate() {
                reschedule(taskID: taskID, to: newDueDate)
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

    private func reschedule(taskID: UUID, to newDueDate: Date) {
        let context = modelContainer.mainContext
        guard let task = task(with: taskID, in: context) else { return }

        task.dueDate = newDueDate
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
