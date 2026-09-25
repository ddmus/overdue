//
//  TaskAlarms.swift
//  overdo
//
//  Created by tomas on 24.09.2026.
//

import AlarmKit
import AppIntents
import SwiftUI

/// Rings a system alarm (AlarmKit) at the due time of every urgent task — like Urgent
/// reminders in Apple's Reminders app. Alarms break through Silent mode and Focus and
/// take over the screen until stopped.
///
/// Each alarm uses its task's id, so a task has at most one. The alert offers Stop
/// and Open; Open launches the app on the task's detail.
enum TaskAlarms {

    /// What each scheduled alarm was built from, keyed by task id — lets `sync` skip
    /// alarms that are already up to date instead of rescheduling them every time.
    private static let signaturesKey = "TaskAlarms.signatures"

    /// The previous sync; each sync waits for it so cancels and schedules don't interleave.
    private static var lastSync: Task<Void, Never>?

    /// Asks for alarm permission if it hasn't been decided yet.
    static func requestAuthorization() async {
        guard AlarmManager.shared.authorizationState == .notDetermined else { return }
        _ = try? await AlarmManager.shared.requestAuthorization()
    }

    /// Makes the scheduled alarms match the urgent tasks among `tasks` (expected to be
    /// the active, non-idea ones): adds or updates alarms for future urgent tasks and
    /// cancels the rest. An alarm that is ringing right now is left alone.
    static func sync(tasks: [TodoItem]) {
        let now = Date.now
        let planned = tasks
            .filter { $0.isUrgent && $0.dueDate > now }
            .map { PlannedAlarm(id: $0.id, fireDate: $0.dueDate, title: $0.text) }

        let previous = lastSync
        lastSync = Task {
            await previous?.value
            await apply(planned)
        }
    }

    /// Cancels a task's alarm, including one that is ringing right now.
    static func cancel(taskID: UUID) {
        try? AlarmManager.shared.cancel(id: taskID)
        var signatures = storedSignatures
        signatures[taskID.uuidString] = nil
        storedSignatures = signatures
    }

    private static func apply(_ planned: [PlannedAlarm]) async {
        let manager = AlarmManager.shared
        guard manager.authorizationState == .authorized else { return }

        let existing = (try? manager.alarms) ?? []
        let plannedIDs = Set(planned.map(\.id))
        var signatures = storedSignatures

        for alarm in existing where !plannedIDs.contains(alarm.id) && alarm.state != .alerting {
            try? manager.cancel(id: alarm.id)
            signatures[alarm.id.uuidString] = nil
        }

        let existingIDs = Set(existing.map(\.id))
        for alarm in planned {
            let key = alarm.id.uuidString
            if existingIDs.contains(alarm.id) {
                if signatures[key] == alarm.signature { continue }
                try? manager.cancel(id: alarm.id)
            }
            do {
                _ = try await manager.schedule(id: alarm.id, configuration: alarm.configuration())
                signatures[key] = alarm.signature
            } catch {
                signatures[key] = nil
            }
        }

        // Forget signatures of alarms that no longer exist (fired or cancelled).
        let liveIDs = existingIDs.union(plannedIDs)
        storedSignatures = signatures.filter { key, _ in
            UUID(uuidString: key).map(liveIDs.contains) ?? false
        }
    }

    private static var storedSignatures: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: signaturesKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: signaturesKey) }
    }

    /// One urgent task's alarm, ready to be turned into an AlarmKit configuration.
    nonisolated private struct PlannedAlarm {
        let id: UUID
        let fireDate: Date
        let title: String

        var signature: String {
            "\(fireDate.timeIntervalSinceReferenceDate)|\(title)"
        }

        func configuration() -> AlarmManager.AlarmConfiguration<TaskAlarmMetadata> {
            let openButton = AlarmButton(
                text: "Open",
                textColor: .white,
                systemImageName: "arrow.up.forward.app"
            )
            let alert = AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: title),
                secondaryButton: openButton,
                secondaryButtonBehavior: .custom
            )
            let attributes = AlarmAttributes<TaskAlarmMetadata>(
                presentation: AlarmPresentation(alert: alert),
                tintColor: .orange
            )
            return .alarm(
                schedule: .fixed(fireDate),
                attributes: attributes,
                secondaryIntent: OpenTaskIntent(taskID: id)
            )
        }
    }
}

/// AlarmKit requires a metadata type; the alarms carry nothing beyond their id.
nonisolated struct TaskAlarmMetadata: AlarmMetadata {}

/// Run by an alarm's Open button: brings the app forward on the task's detail.
struct OpenTaskIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Open Task"
    static let isDiscoverable = false
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Task ID")
    var taskID: String

    init() {}

    init(taskID: UUID) {
        self.taskID = taskID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: taskID) {
            TaskRouter.shared.taskIDToOpen = id
        }
        return .result()
    }
}
