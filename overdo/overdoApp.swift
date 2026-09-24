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
    private let notificationRouter = NotificationRouter()

    init() {
        do {
            // The app has an iCloud entitlement for the JSON backup file, which would
            // otherwise make SwiftData auto-enable CloudKit sync for the store. We
            // handle iCloud ourselves, so disable CloudKit for the model container.
            let configuration = ModelConfiguration(cloudKitDatabase: .none)
            modelContainer = try ModelContainer(for: TodoItem.self, configurations: configuration)
        } catch {
            fatalError("Failed to create the model container: \(error)")
        }

        // The delegate needs the container so it can apply postpone actions, and the
        // router so a tapped reminder can open its task.
        notificationDelegate = NotificationDelegate(modelContainer: modelContainer, router: notificationRouter)
        UNUserNotificationCenter.current().delegate = notificationDelegate

        // Requests alert + sound + badge permission and registers postpone actions.
        TaskNotifications.requestAuthorization()
        TaskNotifications.registerCategories()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(notificationRouter)
        }
        .modelContainer(modelContainer)
    }
}
