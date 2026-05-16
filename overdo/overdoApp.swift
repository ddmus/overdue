//
//  overdoApp.swift
//  overdo
//
//  Created by tomas on 16.05.2026.
//

import SwiftUI
import SwiftData
import UserNotifications

@main
struct overdoApp: App {

    private let modelContainer: ModelContainer
    private let notificationDelegate: NotificationDelegate

    init() {
        do {
            modelContainer = try ModelContainer(for: TodoItem.self)
        } catch {
            fatalError("Failed to create the model container: \(error)")
        }

        // The delegate needs the container so it can apply postpone actions.
        notificationDelegate = NotificationDelegate(modelContainer: modelContainer)
        UNUserNotificationCenter.current().delegate = notificationDelegate

        // Requests alert + sound + badge permission and registers postpone actions.
        TaskNotifications.requestAuthorization()
        TaskNotifications.registerCategories()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
