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

    init() {
        // Badge authorization is required before the app icon badge will show.
        UNUserNotificationCenter.current().requestAuthorization(options: [.badge]) { _, _ in }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: TodoItem.self)
    }
}
