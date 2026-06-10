//
//  TaskBackup.swift
//  overdo
//
//  Created by tomas on 17.05.2026.
//

import Foundation

/// Mirrors the full task list to a single JSON file, overwritten on every change.
///
/// Prefers the app's iCloud Drive container (so the backup survives app deletion and
/// syncs across devices), falling back to the local Documents directory when iCloud
/// is unavailable. Includes completed and soft-deleted tasks, so the file is a
/// complete snapshot. The write is atomic — the file is always a complete copy.
enum TaskBackup {

    /// A plain, Codable mirror of a task — decoupled from the SwiftData model.
    struct Entry: Codable {
        let id: UUID
        let text: String
        let dueDate: Date
        let isCompleted: Bool
        let isDeleted: Bool
        let isTimeSensitive: Bool
    }

    static let fileName = "tasks-backup.json"

    /// Overwrites the backup file with the current task list.
    ///
    /// Model properties are read on the caller's thread (typically the main actor),
    /// then the file work runs in the background — resolving the iCloud container can
    /// block, so it must never run on the main thread.
    static func write(_ tasks: [TodoItem]) {
        let entries = tasks.map {
            Entry(
                id: $0.id,
                text: $0.text,
                dueDate: $0.dueDate,
                isCompleted: $0.isCompleted,
                isDeleted: $0.isDeleted,
                isTimeSensitive: $0.isTimeSensitive
            )
        }

        Task.detached(priority: .utility) {
            persist(entries)
        }
    }

    private static func persist(_ entries: [Entry]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(entries) else { return }

        let url = destinationURL()
        // Backup is best-effort; a failed write must never disrupt the app.
        try? data.write(to: url, options: .atomic)

        #if DEBUG
        let isiCloud = url.path.contains("Mobile Documents") || url.path.contains("CloudDocs")
        print("📦 TaskBackup → \(isiCloud ? "iCloud" : "local"): \(url.path)")
        if let contents = try? String(contentsOf: url, encoding: .utf8) {
            print(contents)
        }
        #endif
    }

    /// The iCloud Drive location when available, otherwise the local Documents file.
    private static func destinationURL() -> URL {
        iCloudFileURL() ?? URL.documentsDirectory.appending(path: fileName)
    }

    /// The backup file inside the app's iCloud Drive container, or `nil` when the
    /// user isn't signed into iCloud / the capability isn't provisioned.
    private static func iCloudFileURL() -> URL? {
        let fileManager = FileManager.default
        guard let container = fileManager.url(forUbiquityContainerIdentifier: nil) else {
            return nil
        }
        let documents = container.appending(path: "Documents")
        try? fileManager.createDirectory(at: documents, withIntermediateDirectories: true)
        return documents.appending(path: fileName)
    }
}
