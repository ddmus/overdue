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
        case create(isIdea: Bool)
        case edit(TodoItem)
        case bulkEdit([TodoItem])

        var id: String {
            switch self {
            case .create(let isIdea): return "create-\(isIdea)"
            case .edit(let task): return "edit-\(task.id.uuidString)"
            case .bulkEdit: return "bulkEdit"
            }
        }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(NotificationRouter.self) private var notificationRouter

    // Scheduled tasks shown in the Tasks list: active, not an idea, soonest due first.
    @Query(filter: #Predicate<TodoItem> { !$0.isCompleted && !$0.isDeleted && !$0.isIdea }, sort: \TodoItem.dueDate)
    private var tasks: [TodoItem]

    // Active ideas shown in the Ideas list: active and flagged as an idea.
    @Query(filter: #Predicate<TodoItem> { !$0.isCompleted && !$0.isDeleted && $0.isIdea }, sort: \TodoItem.dueDate)
    private var ideas: [TodoItem]

    // Every task, including completed and soft-deleted — the source for the backup file.
    @Query private var allTasks: [TodoItem]

    @State private var activeSheet: ActiveSheet?
    @State private var searchText = ""

    // Multi-select state.
    @State private var isSelecting = false
    @State private var selectedTaskIDs: Set<UUID> = []

    // The most recent revertible action, or nil when nothing is undoable.
    @State private var pendingUndo: UndoRecord?

    /// The currently selected items, resolved from their IDs across tasks and ideas.
    private var selectedTasks: [TodoItem] {
        (tasks + ideas).filter { selectedTaskIDs.contains($0.id) }
    }

    var body: some View {
        TabView {
            Tab("Tasks", systemImage: "list.bullet") {
                tasksTab
            }
            Tab("Ideas", systemImage: "lightbulb") {
                ideasTab
            }
            Tab(role: .search) {
                searchTab
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .create(let isIdea):
                TaskSheet(mode: .create(isIdea: isIdea)) { result in
                    modelContext.insert(TodoItem(
                        text: result.text,
                        dueDate: result.dueDate,
                        isTimeSensitive: result.isTimeSensitive,
                        isIdea: result.isIdea
                    ))
                }
            case .edit(let task):
                TaskSheet(mode: .edit(task)) { result in
                    registerUndo("Undo edit", for: [task])
                    task.text = result.text
                    task.dueDate = result.dueDate
                    task.isTimeSensitive = result.isTimeSensitive
                    task.isIdea = result.isIdea
                    // Becoming an idea drops all reminders; any other edit clears the
                    // delivered ones so Notification Center doesn't show stale details.
                    if result.isIdea {
                        TaskNotifications.cancel(taskID: task.id)
                    } else {
                        TaskNotifications.clearDelivered(taskID: task.id)
                    }
                } onComplete: {
                    markDone(task)
                }
            case .bulkEdit(let bulkTasks):
                BulkEditSheet(tasks: bulkTasks) { result in
                    registerUndo("Undo bulk edit", for: bulkTasks)
                    for task in bulkTasks {
                        switch result {
                        case .setDueDate(let newDueDate):
                            task.dueDate = newDueDate
                            task.isIdea = false
                            TaskNotifications.clearDelivered(taskID: task.id)
                        case .makeIdea:
                            task.isIdea = true
                            task.isTimeSensitive = false
                            TaskNotifications.cancel(taskID: task.id)
                        }
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
        .onChange(of: notificationRouter.taskIDToOpen, initial: true) { _, taskID in
            // A tapped reminder opens its task's detail (also on a cold launch).
            guard let taskID else { return }
            notificationRouter.taskIDToOpen = nil
            if let task = allTasks.first(where: { $0.id == taskID && !$0.isCompleted && !$0.isDeleted }) {
                exitSelectionMode()
                activeSheet = .edit(task)
            }
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
            "\(task.id.uuidString)|\(task.dueDate.timeIntervalSinceReferenceDate)|\(task.text)|\(task.isCompleted)|\(task.isDeleted)|\(task.isTimeSensitive)|\(task.isIdea)"
        }
    }

    // MARK: - Tabs

    private var tasksTab: some View {
        NavigationStack {
            // Periodic timeline keeps the calculated relative-time labels live.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                taskList(tasks, now: context.date)
            }
            .navigationTitle(isSelecting ? "\(selectedTaskIDs.count) Selected" : "Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { listToolbar(isIdeaList: false) }
        }
    }

    private var ideasTab: some View {
        NavigationStack {
            ideasList
                .navigationTitle(isSelecting ? "\(selectedTaskIDs.count) Selected" : "Ideas")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { listToolbar(isIdeaList: true) }
        }
    }

    /// Flat, dateless list for ideas (no Overdue/Today/Upcoming sections).
    @ViewBuilder
    private var ideasList: some View {
        if ideas.isEmpty {
            ContentUnavailableView(
                "No ideas",
                systemImage: "lightbulb",
                description: Text("Tap + to capture an idea without a due date.")
            )
        } else {
            List {
                ForEach(ideas) { taskRow($0, now: .now) }
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

    /// The shared toolbar for both the Tasks and Ideas lists. `isIdeaList` makes the
    /// + button create an idea instead of a scheduled task.
    @ToolbarContentBuilder
    private func listToolbar(isIdeaList: Bool) -> some ToolbarContent {
        if let undo = pendingUndo, !isSelecting {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    performUndo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .accessibilityLabel(undo.label)
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if isSelecting {
                selectionToolbarButtons
            } else {
                defaultToolbarButtons(isIdeaList: isIdeaList)
            }
        }
    }

    @ViewBuilder
    private func defaultToolbarButtons(isIdeaList: Bool) -> some View {
        Button {
            enterSelectionMode()
        } label: {
            Image(systemName: "checklist")
        }
        .accessibilityLabel("Select")

        Button {
            activeSheet = .create(isIdea: isIdeaList)
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel(isIdeaList ? "New idea" : "New task")
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
                        delete(task)
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
                registerUndo("Undo reschedule", for: [task])
                task.dueDate = newDueDate
                // Giving an idea a due date promotes it to a scheduled task.
                task.isIdea = false
                TaskNotifications.clearDelivered(taskID: task.id)
            }
        }
    }

    private func markDone(_ task: TodoItem) {
        registerUndo("Undo complete", for: [task])
        task.isCompleted = true
        TaskNotifications.cancel(taskID: task.id)
    }

    private func delete(_ task: TodoItem) {
        registerUndo("Undo delete", for: [task])
        task.isDeleted = true
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

    // MARK: - Undo

    /// A single revertible action, captured just before a change is applied.
    private struct UndoRecord: Identifiable {
        let id = UUID()
        let label: String
        let revert: () -> Void
    }

    /// How long the Undo button stays available after a change.
    private var undoWindow: Duration { .seconds(20) }

    /// Snapshots the given tasks so the change about to happen can be reverted, and
    /// arms the Undo button for `undoWindow`.
    private func registerUndo(_ label: String, for tasks: [TodoItem]) {
        let snapshots = tasks.map { task in
            (task: task,
             text: task.text,
             dueDate: task.dueDate,
             isCompleted: task.isCompleted,
             isDeleted: task.isDeleted,
             isTimeSensitive: task.isTimeSensitive,
             isIdea: task.isIdea)
        }
        let record = UndoRecord(label: label) {
            for snapshot in snapshots {
                snapshot.task.text = snapshot.text
                snapshot.task.dueDate = snapshot.dueDate
                snapshot.task.isCompleted = snapshot.isCompleted
                snapshot.task.isDeleted = snapshot.isDeleted
                snapshot.task.isTimeSensitive = snapshot.isTimeSensitive
                snapshot.task.isIdea = snapshot.isIdea
            }
        }
        withAnimation(toolbarAnimation) { pendingUndo = record }

        // Auto-expire this record after the window (unless a newer one replaced it).
        Task {
            try? await Task.sleep(for: undoWindow)
            if pendingUndo?.id == record.id {
                withAnimation(toolbarAnimation) { pendingUndo = nil }
            }
        }
    }

    private func performUndo() {
        guard let undo = pendingUndo else { return }
        undo.revert()
        withAnimation(toolbarAnimation) { pendingUndo = nil }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: TodoItem.self, inMemory: true)
        .environment(NotificationRouter())
}
