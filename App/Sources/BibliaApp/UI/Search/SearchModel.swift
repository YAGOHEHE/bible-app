import Foundation
import Observation

enum SearchScopeChoice: String, CaseIterable, Identifiable {
    case all, ot, nt, book
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: "Toda la Biblia"
        case .ot: "Antiguo Testamento"
        case .nt: "Nuevo Testamento"
        case .book: "Libro actual"
        }
    }
}

/// Estado de la búsqueda (S05): consulta con debounce cancelable, alcance, resultados y navegación entre coincidencias.
@Observable
@MainActor
final class SearchModel {
    enum Phase: Equatable { case idle, loading, results, empty, failed(String) }

    static let pageSize = 500
    static let debounce: UInt64 = 250_000_000

    var active = false                 // la barra lateral muestra la búsqueda
    var focusToken = 0                 // +1 => enfocar el campo (⌘F)
    var query = ""
    var scope: SearchScopeChoice = .all
    var translationOverride: String?   // nil = versión principal actual
    var phase: Phase = .idle
    var hits: [SearchHit] = []
    var total = 0
    var perBook: [Int: Int] = [:]
    var limit = SearchModel.pageSize
    var selected: Int?                 // índice en `hits`
    var history: [String] = []
    /// Términos de la búsqueda mostrada (los de `hits`), para resaltar.
    var terms: [String] = []

    @ObservationIgnored private let state: AppState
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init(state: AppState) { self.state = state }

    var translationId: String { translationOverride ?? state.translationId }
    var groups: [SearchGroup] { SearchGrouping.group(hits, totals: perBook) }
    var hasMore: Bool { hits.count < total }
    var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var repoScope: SearchRepository.Scope {
        switch scope {
        case .all: .all
        case .ot: .ot
        case .nt: .nt
        case .book: .book(state.book)
        }
    }

    // MARK: activación (⌘F)

    func activate() {
        active = true
        focusToken += 1
        loadHistory()
    }

    func deactivate() { active = false }

    /// Lanza una búsqueda inmediata con ese texto (p. ej. desde "Buscar «…»" en Ir a referencia).
    func start(_ text: String) {
        activate()
        query = text
        runNow()
    }

    // MARK: ejecución

    /// Llamar cuando cambia consulta, alcance o versión: debounce de 250 ms; cancela la anterior.
    func scheduleSearch() {
        task?.cancel()
        limit = Self.pageSize
        guard !trimmedQuery.isEmpty else { reset(); return }
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.debounce)
            guard !Task.isCancelled, let self else { return }
            await self.run()
        }
    }

    /// Intro: busca ya y guarda la consulta en el historial.
    func runNow() {
        task?.cancel()
        limit = Self.pageSize
        guard !trimmedQuery.isEmpty else { reset(); return }
        task = Task { [weak self] in await self?.run(record: true) }
    }

    func showMore() {
        limit += Self.pageSize
        task?.cancel()
        task = Task { [weak self] in await self?.run(keepSelection: true) }
    }

    private func reset() {
        generation += 1
        hits = []; total = 0; perBook = [:]; selected = nil; terms = []
        phase = .idle
        state.clearSearchHighlight()
    }

    /// Ejecuta la consulta fuera del actor principal; descarta resultados obsoletos.
    func run(record: Bool = false, keepSelection: Bool = false) async {
        let q = trimmedQuery
        guard !q.isEmpty, let db = state.bible else { reset(); return }
        generation += 1
        let gen = generation
        if hits.isEmpty { phase = .loading }
        let repo = SearchRepository(db: db)
        let tid = translationId, sc = repoScope, lim = limit
        let result: Result<SearchPage, Error> = await Task.detached(priority: .userInitiated) {
            Result { try repo.page(q, translationId: tid, scope: sc, limit: lim) }
        }.value
        guard !Task.isCancelled, gen == generation else { return }
        switch result {
        case .failure(let e):
            hits = []; total = 0; perBook = [:]; terms = []
            phase = .failed("\(e)")
        case .success(let p):
            hits = p.hits; total = p.total; perBook = p.perBook
            terms = SearchTerms.split(q)
            if !keepSelection { selected = nil }
            phase = p.hits.isEmpty ? .empty : .results
            if record { remember(q) }
        }
    }

    // MARK: abrir / moverse entre coincidencias (⌘G, ⇧⌘G)

    func open(index: Int) {
        guard hits.indices.contains(index) else { return }
        selected = index
        remember(trimmedQuery)
        state.openHit(hits[index], terms: terms)
    }

    func next() { step(+1) }
    func previous() { step(-1) }

    private func step(_ d: Int) {
        guard !hits.isEmpty else { return }
        let n = hits.count
        let i = selected.map { ($0 + d + n) % n } ?? (d > 0 ? 0 : n - 1)
        open(index: i)
    }

    // MARK: historial

    func loadHistory() { history = (try? state.user?.recentSearches()) ?? [] }

    func remember(_ q: String) {
        try? state.user?.addSearch(q)
        loadHistory()
    }

    func clearHistory() {
        try? state.user?.clearSearches()
        history = []
    }
}
