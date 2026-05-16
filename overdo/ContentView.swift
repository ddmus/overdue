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

    // Active (not completed) tasks, soonest due first. Completed tasks are filtered out.
    @Query(filter: #Predicate<TodoItem> { !$0.isCompleted }, sort: \TodoItem.dueDate)
    private var tasks: [TodoItem]

    @State private var activeSheet: ActiveSheet?

    // Multi-select state.
    @State private var isSelecting = false
    @State private var selectedTaskIDs: Set<UUID> = []

    /// The currently selected tasks, resolved from their IDs.
    private var selectedTasks: [TodoItem] {
        tasks.filter { selectedTaskIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            // Periodic timeline keeps the calculated relative-time labels live.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                taskList(now: context.date)
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
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .create:
                TaskSheet(mode: .create) { text, dueDate in
                    modelContext.insert(TodoItem(text: text, dueDate: dueDate))
                }
            case .edit(let task):
                TaskSheet(mode: .edit(task)) { text, dueDate in
                    task.text = text
                    task.dueDate = dueDate
                } onComplete: {
                    task.isCompleted = true
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
        .onChange(of: scenePhase) { _, _ in
            // Catch tasks that crossed their due date while the app was away.
            Badge.set(tasks.filter { $0.isOverdue() }.count)
        }
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
    private func taskList(now: Date) -> some View {
        let overdue = tasks.filter { $0.isOverdue(at: now) }
        let upcoming = tasks.filter { !$0.isOverdue(at: now) }

        Group {
            if tasks.isEmpty {
                ContentUnavailableView(
                    "No tasks",
                    systemImage: "checkmark.circle",
                    description: Text("Tap + to add your first task.")
                )
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
                    if !upcoming.isEmpty {
                        Section("Upcoming") {
                            ForEach(upcoming) { taskRow($0, now: now) }
                        }
                    }
                }
            }
        }
        // Keep the badge current as tasks cross their due date while in use.
        .onChange(of: overdue.count) {
            Badge.set(overdue.count)
        }
    }

    @ViewBuilder
    private func taskRow(_ task: TodoItem, now: Date) -> some View {
        let isSelected = isSelecting && selectedTaskIDs.contains(task.id)

        let row = TaskRow(task: task, now: now)
            .contentShape(Rectangle())
            .onTapGesture {
                if isSelecting {
                    toggleSelection(task)
                } else {
                    activeSheet = .edit(task)
                }
            }
            .listRowBackground(isSelected ? Color.accentColor.opacity(0.15) : nil)

        // Swipe actions only outside selection mode.
        if isSelecting {
            row
        } else {
            row
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        task.isCompleted = true
                    } label: {
                        Label("Complete", systemImage: "checkmark")
                    }
                    .tint(.green)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        modelContext.delete(task)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
        }
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
