//
//  ContentView.swift
//  overdo
//
//  Created by tomas on 16.05.2026.
//

import SwiftUI
import SwiftData

struct ContentView: View {

    /// Which task sheet, if any, is currently presented.
    private enum ActiveSheet: Identifiable {
        case create
        case edit(TodoItem)
        case bulkEdit([TodoItem])

        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let task): return "edit-\(task.id.uuidString)"
            case .bulkEdit: return "bulkEdit"
            }
        }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    // Active tasks shown in the UI: not completed and not deleted, soonest due first.
    @Query(filter: #Predicate<TodoItem> { !$0.isCompleted && !$0.isDeleted }, sort: \TodoItem.dueDate)
    private var tasks: [TodoItem]

    // Every task, including completed and soft-deleted — the source for the backup file.
    @Query private var allTasks: [TodoItem]

    @State private var activeSheet: ActiveSheet?
    @State private var searchText = ""

    // Multi-select state.
    @State private var isSelecting = false
    @State private var selectedTaskIDs: Set<UUID> = []

    /// The currently selected tasks, resolved from their IDs.
    private var selectedTasks: [TodoItem] {
        tasks.filter { selectedTaskIDs.contains($0.id) }
    }

    var body: some View {
        TabView {
            Tab("Tasks", systemImage: "list.bullet") {
                tasksTab
            }
            Tab(role: .search) {
                searchTab
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .create:
                TaskSheet(mode: .create) { text, dueDate, isTimeSensitive in
                    modelContext.insert(TodoItem(
                        text: text,
                        dueDate: dueDate,
                        isTimeSensitive: isTimeSensitive
                    ))
                }
            case .edit(let task):
                TaskSheet(mode: .edit(task)) { text, dueDate, isTimeSensitive in
                    task.text = text
                    task.dueDate = dueDate
                    task.isTimeSensitive = isTimeSensitive
                } onComplete: {
                    task.isCompleted = true
                    TaskNotifications.cancel(taskID: task.id)
                }
            case .bulkEdit(let bulkTasks):
                BulkEditSheet(tasks: bulkTasks) { newDueDate in
                    for task in bulkTasks {
                        task.dueDate = newDueDate
                    }
                    exitSelectionMode()
                }
            }
        }
        .task {
            // Schedule reminders and refresh the backup on launch.
            TaskNotifications.sync(tasks: tasks)
            TaskBackup.write(allTasks)
        }
        .onChange(of: notificationSnapshot) {
            // Any add / edit / complete / delete reschedules all reminders so the
            // badge counts baked into each notification stay correct.
            TaskNotifications.sync(tasks: tasks)
        }
        .onChange(of: backupSnapshot) {
            // Mirror every change (including completes and soft-deletes) to the file.
            TaskBackup.write(allTasks)
        }
        .onChange(of: scenePhase) { _, _ in
            // Catch tasks that crossed their due date while the app was away:
            // refresh the badge and start their repeating reminders.
            Badge.set(tasks.filter { $0.isOverdue() }.count)
            TaskNotifications.sync(tasks: tasks)
        }
    }

    /// Changes whenever a task's identity, due date, text or membership changes —
    /// the trigger for rescheduling reminders.
    private var notificationSnapshot: [String] {
        tasks.map { task in
            "\(task.id.uuidString)|\(task.dueDate.timeIntervalSinceReferenceDate)|\(task.text)|\(task.isTimeSensitive)"
        }
    }

    /// Changes on any edit across *all* tasks (including completed and deleted) —
    /// the trigger for rewriting the backup file.
    private var backupSnapshot: [String] {
        allTasks.map { task in
            "\(task.id.uuidString)|\(task.dueDate.timeIntervalSinceReferenceDate)|\(task.text)|\(task.isCompleted)|\(task.isDeleted)|\(task.isTimeSensitive)"
        }
    }

    // MARK: - Tabs

    private var tasksTab: some View {
        NavigationStack {
            // Periodic timeline keeps the calculated relative-time labels live.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                taskList(tasks, now: context.date)
            }
            .navigationTitle(isSelecting ? "\(selectedTaskIDs.count) Selected" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if isSelecting {
                        selectionToolbarButtons
                    } else {
                        defaultToolbarButtons
                    }
                }
            }
        }
    }

    private var searchTab: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                taskList(filteredTasks, now: context.date, searching: true)
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
        }
        .searchable(text: $searchText, prompt: "Search tasks")
    }

    /// Active tasks whose text contains the search string (all of them when empty).
    private var filteredTasks: [TodoItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return tasks }
        return tasks.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var defaultToolbarButtons: some View {
        Button {
            enterSelectionMode()
        } label: {
            Image(systemName: "checklist")
        }
        .accessibilityLabel("Select tasks")

        Button {
            activeSheet = .create
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("New task")
    }

    @ViewBuilder
    private var selectionToolbarButtons: some View {
        if !selectedTaskIDs.isEmpty {
            Button {
                activeSheet = .bulkEdit(selectedTasks)
            } label: {
                Image(systemName: "calendar.badge.clock")
            }
            .accessibilityLabel("Edit selected tasks")
        }

        Button {
            exitSelectionMode()
        } label: {
            Image(systemName: "xmark")
        }
        .accessibilityLabel("Done selecting")
    }

    // MARK: - Task list

    @ViewBuilder
    private func taskList(_ source: [TodoItem], now: Date, searching: Bool = false) -> some View {
        let overdue = source.filter { $0.isOverdue(at: now) }
        let upcoming = source.filter { !$0.isOverdue(at: now) }
        let today = upcoming.filter { Calendar.current.isDate($0.dueDate, inSameDayAs: now) }
        let later = upcoming.filter { !Calendar.current.isDate($0.dueDate, inSameDayAs: now) }

        Group {
            if source.isEmpty {
                if searching {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ContentUnavailableView(
                        "No tasks",
                        systemImage: "checkmark.circle",
                        description: Text("Tap + to add your first task.")
                    )
                }
            } else {
                List {
                    if !overdue.isEmpty {
                        Section {
                            ForEach(overdue) { taskRow($0, now: now) }
                        } header: {
                            Text("Overdue")
                                .foregroundStyle(.red)
                        }
                    }
                    if !today.isEmpty {
                        Section("Today") {
                            ForEach(today) { taskRow($0, now: now) }
                        }
                    }
                    if !later.isEmpty {
                        Section("Upcoming") {
                            ForEach(later) { taskRow($0, now: now, showsDueDay: true) }
                        }
                    }
                }
            }
        }
        // When a task crosses its due date while the app is open, refresh the badge
        // and reschedule reminders so the overdue task starts its repeating reminder.
        // Driven by the full list only — the filtered search list must not interfere.
        .onChange(of: searching ? 0 : tasks.filter { $0.isOverdue(at: now) }.count) { _, newCount in
            guard !searching else { return }
            Badge.set(newCount)
            TaskNotifications.sync(tasks: tasks)
        }
    }

    @ViewBuilder
    private func taskRow(_ task: TodoItem, now: Date, showsDueDay: Bool = false) -> some View {
        let isSelected = isSelecting && selectedTaskIDs.contains(task.id)

        let row = TaskRow(task: task, now: now, showsDueDay: showsDueDay)
            .contentShape(Rectangle())
            .onTapGesture {
                if isSelecting {
                    toggleSelection(task)
                } else {
                    activeSheet = .edit(task)
                }
            }
            .listRowBackground(isSelected ? Color.accentColor.opacity(0.15) : nil)

        // Swipe actions and context menu only outside selection mode.
        if isSelecting {
            row
        } else {
            row
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        markDone(task)
                    } label: {
                        Label("Complete", systemImage: "checkmark")
                    }
                    .tint(.green)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        task.isDeleted = true
                        TaskNotifications.cancel(taskID: task.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .contextMenu {
                    ForEach(TaskNotifications.Action.Group.allCases, id: \.self) { group in
                        Section {
                            ForEach(actions(in: group), id: \.self) { action in
                                Button {
                                    apply(action, to: task)
                                } label: {
                                    Label(action.title, systemImage: action.iconName)
                                }
                            }
                        }
                    }
                }
        }
    }

    // MARK: - Task actions

    private func actions(in group: TaskNotifications.Action.Group) -> [TaskNotifications.Action] {
        TaskNotifications.Action.allCases.filter { $0.group == group }
    }

    /// Applies a context-menu / notification action to a task.
    private func apply(_ action: TaskNotifications.Action, to task: TodoItem) {
        switch action {
        case .markDone:
            markDone(task)
        case .postpone15m, .postpone1h, .postpone1d, .at9, .at12, .at18, .at20:
            if let newDueDate = action.resolvedDueDate() {
                task.dueDate = newDueDate
            }
        }
    }

    private func markDone(_ task: TodoItem) {
        task.isCompleted = true
        TaskNotifications.cancel(taskID: task.id)
    }

    // MARK: - Selection

    /// Spring with a small bounce, used for toolbar icon add/remove transitions.
    private var toolbarAnimation: Animation { .bouncy(duration: 0.4) }

    private func enterSelectionMode() {
        selectedTaskIDs.removeAll()
        withAnimation(toolbarAnimation) {
            isSelecting = true
        }
    }

    private func exitSelectionMode() {
        withAnimation(toolbarAnimation) {
            isSelecting = false
        }
        selectedTaskIDs.removeAll()
    }

    private func toggleSelection(_ task: TodoItem) {
        withAnimation(toolbarAnimation) {
            if selectedTaskIDs.contains(task.id) {
                selectedTaskIDs.remove(task.id)
            } else {
                selectedTaskIDs.insert(task.id)
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: TodoItem.self, inMemory: true)
}
