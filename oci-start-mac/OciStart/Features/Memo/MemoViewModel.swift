import Foundation
import Combine

@MainActor
final class MemoViewModel: ObservableObject {
    @Published var items: [MemoItem] = []
    @Published var searchText = ""
    @Published var activeForm: MemoFormState?
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var errorText: String?

    private let session: AppSession
    private var service: MemoService { MemoService(baseURL: session.serverURL) }

    var filtered: [MemoItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return items }
        return items.filter {
            $0.title.localizedCaseInsensitiveContains(q)
                || $0.summary.localizedCaseInsensitiveContains(q)
                || $0.content.localizedCaseInsensitiveContains(q)
        }
    }

    init(session: AppSession = .shared) {
        self.session = session
    }

    func start() {
        Task { await reload() }
    }

    func reload() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            items = try await service.list()
        } catch {
            errorText = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func openCreate() {
        activeForm = MemoFormState()
    }

    func openEdit(_ item: MemoItem) {
        activeForm = MemoFormState(
            id: item.id,
            title: item.title,
            summary: item.summary,
            content: item.content
        )
    }

    func saveForm() {
        Task { await performSave() }
    }

    private func performSave() async {
        guard let form = activeForm else { return }
        let title = form.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = form.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            ToastCenter.shared.error("请填写标题")
            return
        }
        guard !content.isEmpty else {
            ToastCenter.shared.error("请填写内容")
            return
        }
        let summary = form.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let editId = form.id
        isSaving = true
        defer { isSaving = false }
        do {
            try await LoadingHUD.shared.during {
                if let id = editId {
                    _ = try await service.update(id: id, title: title, summary: summary, content: content)
                } else {
                    _ = try await service.create(title: title, summary: summary, content: content)
                }
            }
            activeForm = nil
            await reload()
        } catch {
            ToastCenter.shared.error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func delete(_ item: MemoItem) {
        let ok = AppAlert.confirm(
            title: "删除备忘",
            message: "确定删除「\(item.title)」？此操作不可恢复。",
            confirmTitle: "删除"
        )
        guard ok else { return }
        Task { await performDelete(item) }
    }

    private func performDelete(_ item: MemoItem) async {
        do {
            try await LoadingHUD.shared.during {
                try await service.delete(id: item.id)
            }
            await reload()
        } catch {
            ToastCenter.shared.error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
