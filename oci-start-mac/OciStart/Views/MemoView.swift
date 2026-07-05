import SwiftUI

struct MemoView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedMemo: Memo?
    @State private var editTitle = ""
    @State private var editContent = ""
    @State private var isDirty = false
    @State private var showDeleteAlert = false
    @State private var isCreating = false

    var body: some View {
        HSplitView {
            memoList.frame(minWidth: 200, maxWidth: 260)
            editorPanel
        }
        .navigationTitle("便签")
        .toolbar { toolbarItems }
        .alert(isPresented: $showDeleteAlert) {
            Alert(
                title: Text("确认删除"),
                message: Text("删除便签「\(selectedMemo?.displayTitle ?? "")」？"),
                primaryButton: .destructive(Text("删除")) { deleteSelected() },
                secondaryButton: .cancel()
            )
        }
        .onAppear {
            if appState.memos.isEmpty { Task { await appState.loadMemos() } }
        }
    }

    // MARK: - Memo List

    private var memoList: some View {
        VStack(spacing: 0) {
            List(appState.memos, selection: $selectedMemo) { memo in
                VStack(alignment: .leading, spacing: 4) {
                    Text(memo.displayTitle).fontWeight(.medium).lineLimit(1)
                    Text(memo.content ?? "").font(.caption).foregroundColor(.secondary)
                        .lineLimit(2)
                    Text(memo.updateTime.map { String($0.prefix(10)) } ?? "")
                        .font(.caption2).foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
                .tag(memo)
            }
            .listStyle(.sidebar)
            .onChange(of: selectedMemo) { m in
                guard let m = m else { return }
                editTitle   = m.title   ?? ""
                editContent = m.content ?? ""
                isDirty = false
                isCreating = false
            }
        }
    }

    // MARK: - Editor Panel

    private var editorPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            if selectedMemo != nil || isCreating {
                // Title field
                TextField("标题", text: $editTitle)
                    .font(.title3.weight(.semibold))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 8)
                    .onChange(of: editTitle) { _ in isDirty = true }

                Divider().padding(.horizontal, 20)

                // Content editor
                TextEditor(text: $editContent)
                    .font(.body)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .onChange(of: editContent) { _ in isDirty = true }

                // Save bar
                if isDirty {
                    Divider()
                    HStack {
                        Spacer()
                        Button("取消") { revertEdits() }
                            .keyboardShortcut(.escape)
                        Button("保存") { Task { await saveEdits() } }
                            .buttonStyle(ProminentButton())
                            .keyboardShortcut("s", modifiers: .command)
                    }
                    .padding(.horizontal, 20).padding(.vertical, 10)
                }
            } else {
                VStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "note.text").font(.largeTitle).foregroundColor(.secondary)
                        Text("选择便签或新建").foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Button(action: createNew) {
                Label("新建", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: .command)
        }
        ToolbarItem(placement: .automatic) {
            Button(action: { showDeleteAlert = true }) {
                Label("删除", systemImage: "trash")
            }
            .disabled(selectedMemo == nil)
        }
    }

    // MARK: - Actions

    private func createNew() {
        selectedMemo = nil
        editTitle   = ""
        editContent = ""
        isDirty     = true
        isCreating  = true
    }

    private func saveEdits() async {
        if isCreating {
            if let newMemo = await appState.createMemo(title: editTitle, content: editContent) {
                selectedMemo = newMemo
                isCreating = false
                isDirty = false
            }
        } else if let id = selectedMemo?.id {
            await appState.updateMemo(id: id, title: editTitle, content: editContent)
            if let idx = appState.memos.firstIndex(where: { $0.id == id }) {
                selectedMemo = appState.memos[idx]
            }
            isDirty = false
        }
    }

    private func revertEdits() {
        if isCreating {
            isCreating = false
            selectedMemo = nil
        } else if let m = selectedMemo {
            editTitle   = m.title   ?? ""
            editContent = m.content ?? ""
        }
        isDirty = false
    }

    private func deleteSelected() {
        guard let id = selectedMemo?.id else { return }
        Task {
            await appState.deleteMemo(id: id)
            selectedMemo = nil
            editTitle = ""; editContent = ""
            isCreating = false; isDirty = false
        }
    }
}
