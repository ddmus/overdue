//
//  NotificationDelegate.swift
//  overdo
//
//  Created by tomas on 16.05.2026.
//

import UserNotifications

/// Lets a due reminder appear as a banner even while the app is in the foreground.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
