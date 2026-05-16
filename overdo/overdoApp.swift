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

    private let notificationDelegate = NotificationDelegate()

    init() {
        // Allows due reminders to show while the app is in the foreground.
        UNUserNotificationCenter.current().delegate = notificationDelegate
        // Requests alert + sound + badge permission for due reminders.
        TaskNotifications.requestAuthorization()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: TodoItem.self)
    }
}
