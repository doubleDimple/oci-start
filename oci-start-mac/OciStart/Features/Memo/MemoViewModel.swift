import Foundation
import Combine

@MainActor
final class MemoViewModel: ObservableObject {
    enum Screen { case list, read, edit }
    @Published private(set) var items: [MemoItem] = []
    @Published var searchText = "" { didSet { page.page = 0; updatePage() } }
    @Published var page = PageState(size: 10)
    @Published private(set) var screen: Screen = .list
    @Published var activeForm: MemoFormState?
    @Published private(set) var detail: MemoItem?
    @Published private(set) var editorID = UUID()
    @Published private(set) var isLoading = false
    @Published private(set) var detailLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var errorText: String?
    @Published private(set) var detailError: String?
    @Published private(set) var mutationError: String?
    @Published private(set) var feedback: String?
    @Published private(set) var requiresReview = false
    @Published private(set) var showSavedVersion = false
    @Published private(set) var detailExists: Bool?
    @Published private(set) var reviewReady = false

    private var baseline: MemoFormState?
    private var loaded = false
    private var selectedID: Int64?
    private var reviewID: Int64?
    private var listSequence = 0
    private var detailSequence = 0
    private var listRevision = 0
    private var detailRevision = 0
    private var reviewAfterList = 0
    private var reviewAfterDetail = 0
    private var active = false
    private var lifecycle = UUID()
    private let session: AppSession
    private var service: MemoService { MemoService(baseURL: session.serverURL) }
    private var language: LanguageManager { .shared }

    var filtered: [MemoItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        return items.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.summary.localizedCaseInsensitiveContains(query)
                || $0.content.localizedCaseInsensitiveContains(query)
        }
    }
    var visibleItems: [MemoItem] { Array(filtered.dropFirst(page.page * page.size).prefix(page.size)) }
    var dirty: Bool { screen == .edit && activeForm != baseline }
    var editorDisabled: Bool { isSaving || requiresReview }
    var canMutate: Bool { loaded && !isLoading && errorText == nil && !detailLoading && !isSaving && !requiresReview }
    var detailReady: Bool { detailExists == true && detailError == nil && !detailLoading && MemoJSON.validRevision(detail?.revision) }
    var canSave: Bool {
        canMutate && dirty && (activeForm?.id == nil || (detailReady && activeForm?.revision == detail?.revision))
    }

    init(session: AppSession = .shared) { self.session = session }

    func start() {
        guard !active else { return }
        active = true
        lifecycle = UUID()
        Task { await reload() }
    }

    func stop() {
        active = false
        lifecycle = UUID()
        listSequence += 1
        detailSequence += 1
    }

    func updatePage() {
        page.totalElements = Int64(filtered.count)
        page.totalPages = max(1, Int(ceil(Double(filtered.count) / Double(max(1, page.size)))))
        page.page = max(0, min(page.page, page.totalPages - 1))
    }

    func reload() async {
        guard active, !isSaving else { return }
        await loadList()
        if screen == .read, let id = selectedID { await loadDetail(id) }
        updateReviewReady()
    }

    private func loadList() async {
        listSequence += 1
        let sequence = listSequence, token = lifecycle, api = service
        isLoading = true
        errorText = nil
        do {
            let result = try await api.list()
            guard active, lifecycle == token, listSequence == sequence else { return }
            items = result
            loaded = true
            listRevision += 1
            updatePage()
        } catch {
            guard active, lifecycle == token, listSequence == sequence else { return }
            errorText = message(error)
        }
        guard active, lifecycle == token, listSequence == sequence else { return }
        isLoading = false
        updateReviewReady()
    }

    private func loadDetail(_ id: Int64) async {
        detailSequence += 1
        let sequence = detailSequence, token = lifecycle, api = service
        if selectedID != id { detail = nil; detailExists = nil }
        selectedID = id
        detailLoading = true
        detailError = nil
        do {
            let record = try await api.get(id: id)
            guard active, lifecycle == token, detailSequence == sequence, selectedID == id else { return }
            detail = record
            detailExists = true
            detailRevision += 1
        } catch {
            guard active, lifecycle == token, detailSequence == sequence, selectedID == id else { return }
            detailError = message(error)
            if let failure = error as? MemoFailure, failure.key == .notFound {
                detail = nil
                detailExists = false
                detailRevision += 1
            } else { detailExists = nil }
        }
        guard active, lifecycle == token, detailSequence == sequence else { return }
        detailLoading = false
        updateReviewReady()
    }

    func open(_ item: MemoItem, edit: Bool = false, remove: Bool = false) {
        guard !isSaving, !requiresReview, (!edit && !remove) || canMutate else { return }
        clearDraft()
        clearFeedback()
        screen = .read
        Task {
            await loadDetail(item.id)
            guard active, selectedID == item.id, detailReady else { return }
            if edit { editCurrent() }
            if remove { deleteCurrent() }
        }
    }

    func openCreate() {
        guard canMutate else { return }
        selectedID = nil
        detail = nil
        detailExists = nil
        detailError = nil
        enterEditor(nil)
    }

    func editCurrent() {
        guard canMutate, detailReady, let record = detail else { return }
        enterEditor(record)
    }

    private func enterEditor(_ record: MemoItem?) {
        activeForm = MemoFormState(item: record)
        baseline = activeForm
        editorID = UUID()
        showSavedVersion = false
        clearFeedback()
        screen = .edit
    }

    func clearEditor() {
        guard !editorDisabled else { return }
        guard AppAlert.confirm(title: language.text("清空草稿", "Clear draft"),
                               message: language.text("清空当前标题、摘要和正文？已保存的笔记不受影响。", "Clear the draft title, summary, and body? The saved note is unchanged."),
                               confirmTitle: language.text("清空", "Clear"), cancelTitle: language.text("取消", "Cancel")) else { return }
        activeForm?.title = ""
        activeForm?.summary = ""
        activeForm?.content = ""
        activeForm?.htmlContent = nil
        editorID = UUID()
    }

    func updateDocument(text: String, html: String) {
        guard !editorDisabled else { return }
        activeForm?.content = text
        activeForm?.htmlContent = html
        mutationError = nil
    }

    func canLeave() -> Bool {
        if isSaving || requiresReview {
            AppAlert.info(title: language.text("笔记操作尚未结束", "Note operation is pending"),
                          message: language.text("请等待提交完成，或先重新读取并核对未知结果。", "Wait for submission, or reload and review the uncertain result first."))
            return false
        }
        guard dirty else { return true }
        return AppAlert.confirm(title: language.text("放弃未保存的修改？", "Discard unsaved changes?"),
                                message: language.text("离开后当前草稿将丢失。", "The current draft will be lost when you leave."),
                                confirmTitle: language.text("放弃修改", "Discard"), cancelTitle: language.text("继续编辑", "Keep editing"))
    }

    func back() {
        guard canLeave() else { return }
        clearDraft()
        detail = nil
        detailExists = nil
        detailError = nil
        selectedID = nil
        screen = .list
        detailSequence += 1
        detailLoading = false
    }

    private func clearDraft() { activeForm = nil; baseline = nil; showSavedVersion = false }
    func clearFeedback() { feedback = nil; mutationError = nil }

    func saveForm() {
        guard canSave, let draft = activeForm else { return }
        let snapshot: MemoFormState
        do { snapshot = try draft.normalized() }
        catch { mutationError = message(error); return }
        // Freeze both the revision and content before starting the one write.
        isSaving = true
        clearFeedback()
        let api = service, token = lifecycle
        Task {
            do {
                let receipt = try await api.save(snapshot)
                guard active, token == lifecycle else { return }
                clearDraft()
                detail = receipt
                selectedID = receipt.id
                detailExists = true
                screen = .read
                feedback = language.text("笔记已保存。", "Note saved.")
                await readBack(id: receipt.id)
            } catch {
                guard active, token == lifecycle else { return }
                await handleMutationFailure(error, id: snapshot.id)
            }
            guard active, token == lifecycle else { return }
            isSaving = false
            updateReviewReady()
        }
    }

    func deleteCurrent() {
        guard canMutate, detailReady, let record = detail else { return }
        guard AppAlert.confirm(title: language.text("删除笔记", "Delete note"),
                               message: language.text("确定删除「\(record.title)」？此操作不可恢复。", "Delete “\(record.title)”? This cannot be undone."),
                               confirmTitle: language.text("删除", "Delete"), cancelTitle: language.text("取消", "Cancel")) else { return }
        guard canMutate, detail?.revision == record.revision else { return }
        isSaving = true
        clearFeedback()
        let api = service, token = lifecycle
        Task {
            do {
                try await api.delete(record)
                guard active, token == lifecycle else { return }
                items.removeAll { $0.id == record.id }
                clearDraft()
                detail = nil
                selectedID = nil
                detailExists = false
                screen = .list
                feedback = language.text("笔记已删除。", "Note deleted.")
                await loadList()
            } catch {
                guard active, token == lifecycle else { return }
                await handleMutationFailure(error, id: record.id)
            }
            guard active, token == lifecycle else { return }
            isSaving = false
            updateReviewReady()
        }
    }

    private func handleMutationFailure(_ error: Error, id: Int64?) async {
        let failure = (error as? MemoFailure) ?? MemoFailure(key: .requestFailed, writeAttempted: true)
        mutationError = failure.errorDescription
        if failure.writeAttempted {
            requiresReview = true
            reviewID = id
            reviewAfterList = listRevision + 1
            reviewAfterDetail = detailRevision + 1
            showSavedVersion = true
            await readBack(id: id)
        } else if failure.key == .conflict || failure.key == .notFound {
            showSavedVersion = true
            await readBack(id: id)
        }
    }

    private func readBack(id: Int64?) async {
        await loadList()
        if let id = id { await loadDetail(id) }
    }

    func recheck() {
        guard !isSaving else { return }
        Task {
            await readBack(id: reviewID ?? activeForm?.id ?? selectedID)
            updateReviewReady()
        }
    }

    private func updateReviewReady() {
        reviewReady = requiresReview && !isSaving && loaded && !isLoading && errorText == nil
            && listRevision >= reviewAfterList && (reviewID == nil
                || (selectedID == reviewID && !detailLoading && detailRevision >= reviewAfterDetail
                    && (detailExists == false || detailReady)))
    }

    func acknowledgeReview() {
        guard reviewReady else { return }
        requiresReview = false
        reviewReady = false
        reviewID = nil
        mutationError = nil
    }

    func useSavedVersion() {
        guard !isSaving, !requiresReview, detailReady, let record = detail, canLeave() else { return }
        enterEditor(record)
    }

    func keepAsNew() {
        guard canMutate, activeForm != nil else { return }
        activeForm?.id = nil
        activeForm?.revision = nil
        baseline = nil
        selectedID = nil
        detail = nil
        detailExists = nil
        detailError = nil
        showSavedVersion = false
        clearFeedback()
    }

    private func message(_ error: Error) -> String {
        (error as? MemoFailure)?.errorDescription ?? language.text("笔记请求失败，请重新读取。", "The note request failed. Reload to check.")
    }
}
