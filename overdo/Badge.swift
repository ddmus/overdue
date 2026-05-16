//
//  Badge.swift
//  overdo
//
//  Created by tomas on 16.05.2026.
//

import UserNotifications

/// Updates the app icon badge, which reflects the number of overdue tasks.
enum Badge {
    static func set(_ count: Int) {
        UNUserNotificationCenter.current().setBadgeCount(count)
    }
}
