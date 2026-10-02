//
//  TaskAlarms.swift
//  overdo
//
//  Created by tomas on 24.09.2026.
//

import ActivityKit
import AlarmKit
import SwiftUI

/// Rings a system alarm (AlarmKit) at the due time of every urgent task — like Urgent
/// reminders in Apple's Reminders app. Alarms break through Silent mode and Focus and
/// take over the screen until stopped.
///
/// Every alarm gets a fresh id; `records` maps each task to its current alarm. Any change
/// to a task ends its alarm — even one that is ringing or snoozed — and, if the task is
/// still urgent and upcoming, schedules a new one. Reusing an id right after cancelling
/// it is unreliable, which is why ids are never reused. The alert offers Stop and
/// Snooze; Snooze rings the same alarm again `snoozeDuration` later.
enum TaskAlarms {

    /// How long Snooze silences a ringing alarm.
    nonisolated private static let snoozeDuration: TimeInterval = 10 * 60

    /// Where `records` is persisted.
    private static let recordsKey = "TaskAlarms.records"

    /// The previous sync; each sync waits for it so cancels and schedules don't interleave.
    private static var lastSync: Task<Void, Never>?

    /// Asks for alarm permission if it hasn't been decided yet.
    static func requestAuthorization() async {
        guard AlarmManager.shared.authorizationState == .notDetermined else { return }
        _ = try? await AlarmManager.shared.requestAuthorization()
    }

    /// Makes the alarms match `tasks` (expected to be the active, non-idea ones). A task
    /// that hasn't changed keeps its alarm as is, so one that just became overdue keeps
    /// ringing or snoozing. Alarms of tasks not in `tasks` are cancelled.
    static func sync(tasks: [TodoItem]) {
        let now = Date.now
        let snapshots = tasks.map { task in
            TaskSnapshot(
                taskID: task.id,
                isUrgent: task.isUrgent,
                isUpcoming: task.dueDate > now,
                alarm: PlannedAlarm(fireDate: task.dueDate, title: task.text, sound: task.alarmSound)
            )
        }

        let previous = lastSync
        lastSync = Task {
            await previous?.value
            await apply(snapshots)
        }
    }

    /// Cancels a task's alarm, including one that is ringing or snoozed right now.
    static func cancel(taskID: UUID) {
        var records = storedRecords
        if let record = records.removeValue(forKey: taskID) {
            try? AlarmManager.shared.cancel(id: record.alarmID)
            storedRecords = records
        }
    }

    private static func apply(_ snapshots: [TaskSnapshot]) async {
        let manager = AlarmManager.shared
        guard manager.authorizationState == .authorized else { return }

        let liveAlarmIDs = Set(((try? manager.alarms) ?? []).map(\.id))
        let records = storedRecords
        var keptRecords: [UUID: Record] = [:]

        for task in snapshots {
            let signature = task.signature
            if let record = records[task.taskID], liveAlarmIDs.contains(record.alarmID) {
                if record.signature == signature {
                    keptRecords[task.taskID] = record
                    continue
                }
                // The task changed: end its alarm whatever state it is in.
                try? manager.cancel(id: record.alarmID)
            }
            guard task.isUrgent && task.isUpcoming else { continue }

            let alarmID = UUID()
            if (try? await manager.schedule(id: alarmID, configuration: task.alarm.configuration())) != nil {
                keptRecords[task.taskID] = Record(alarmID: alarmID, signature: signature)
            }
        }

        // Alarms of completed, deleted or idea tasks, and any other strays.
        let keptAlarmIDs = Set(keptRecords.values.map(\.alarmID))
        for alarmID in liveAlarmIDs where !keptAlarmIDs.contains(alarmID) {
            try? manager.cancel(id: alarmID)
        }

        storedRecords = keptRecords
    }

    /// Each task's current alarm, keyed by task id.
    private static var storedRecords: [UUID: Record] {
        get {
            guard let data = UserDefaults.standard.data(forKey: recordsKey) else { return [:] }
            return (try? JSONDecoder().decode([UUID: Record].self, from: data)) ?? [:]
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: recordsKey)
        }
    }

    /// A task's alarm and what it was built from — a different signature means the task
    /// changed since the alarm was scheduled.
    nonisolated private struct Record: Codable {
        let alarmID: UUID
        let signature: String
    }

    /// The alarm-relevant state of one task, captured on the main actor.
    nonisolated private struct TaskSnapshot {
        let taskID: UUID
        let isUrgent: Bool
        let isUpcoming: Bool
        let alarm: PlannedAlarm

        var signature: String {
            "\(isUrgent)|\(alarm.fireDate.timeIntervalSinceReferenceDate)|\(alarm.title)|\(alarm.sound.rawValue)"
        }
    }

    /// One urgent task's alarm, ready to be turned into an AlarmKit configuration.
    nonisolated private struct PlannedAlarm {
        let fireDate: Date
        let title: String
        let sound: AlarmSound

        func configuration() -> AlarmManager.AlarmConfiguration<TaskAlarmMetadata> {
            let snoozeButton = AlarmButton(
                text: "Snooze",
                textColor: .white,
                systemImageName: "zzz"
            )
            // `.countdown` makes Snooze restart the alarm's post-alert countdown, after
            // which it rings again.
            let alert = AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: title),
                secondaryButton: snoozeButton,
                secondaryButtonBehavior: .countdown
            )
            let countdown = AlarmPresentation.Countdown(
                title: LocalizedStringResource(stringLiteral: title)
            )
            let attributes = AlarmAttributes<TaskAlarmMetadata>(
                presentation: AlarmPresentation(alert: alert, countdown: countdown),
                tintColor: .orange
            )
            return AlarmManager.AlarmConfiguration(
                countdownDuration: Alarm.CountdownDuration(preAlert: nil, postAlert: snoozeDuration),
                schedule: .fixed(fireDate),
                attributes: attributes,
                sound: sound.alertSound
            )
        }
    }
}

/// How an urgent task's alarm sounds. Every option still takes over the screen, shows
/// the Live Activity and reaches a paired Apple Watch.
nonisolated enum AlarmSound: String, CaseIterable, Identifiable {
    /// No sound at all — the alert, any vibration and the watch do the work.
    case silent
    /// A soft chime bundled with the app: one quiet ping every 8 seconds.
    case gentle
    /// The standard iOS alarm tone.
    case loud

    var id: Self { self }

    var title: String {
        switch self {
        case .silent: "Silent"
        case .gentle: "Gentle"
        case .loud: "Loud"
        }
    }

    var iconName: String {
        switch self {
        case .silent: "speaker.slash"
        case .gentle: "speaker.wave.1"
        case .loud: "speaker.wave.3"
        }
    }

    /// Explains the option in the task sheet.
    var summary: String {
        switch self {
        case .silent: "Urgent shows an alarm at the due time with no sound — on screen, in the Live Activity and on Apple Watch."
        case .gentle: "Urgent rings an alarm at the due time with a soft chime every few seconds."
        case .loud: "Urgent rings the standard iOS alarm at the due time, even in Silent mode or Focus."
        }
    }

    /// The sound file the alarm loops; `silent.caf` and `subtle-chime.caf` are generated
    /// by `scripts/make-alarm-sounds.py`.
    var alertSound: AlertConfiguration.AlertSound {
        switch self {
        case .silent: .named("silent.caf")
        case .gentle: .named("subtle-chime.caf")
        case .loud: .default
        }
    }
}
