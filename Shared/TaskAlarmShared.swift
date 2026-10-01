//
//  TaskAlarmShared.swift
//  overdo
//
//  Created by tomas on 02.10.2026.
//

import AlarmKit
import AppIntents

/// AlarmKit requires a metadata type; the alarms carry nothing beyond their id.
/// Shared by the app (which schedules the alarms) and the widget extension (which
/// draws their Live Activity), so both see the same `AlarmAttributes` type.
nonisolated struct TaskAlarmMetadata: AlarmMetadata {}

/// Run by the Stop button in an urgent task's Live Activity: ends the alarm, whether
/// it is ringing or snoozed.
struct StopTaskAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Alarm"
    static let isDiscoverable = false

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() {}

    init(alarmID: UUID) {
        self.alarmID = alarmID.uuidString
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) {
            try? AlarmManager.shared.cancel(id: id)
        }
        return .result()
    }
}
