import AppKit
import Foundation
import BibliaCore

/// Alcance de la búsqueda (selector «Toda / AT / NT / Libro actual»).
public enum SearchScopeChoice: Int, CaseIterable {
    case all, ot, nt, currentBook
    public var label: String {
        switch self {
        case .all: return "Toda la Biblia"
        case .ot: return "Antiguo Testamento"
        case .nt: return "Nuevo Testamento"
        case .currentBook: return "Libro actual"
        }
    }
    public func scope(currentBook: Int) -> SearchRepository.Scope {
        switch self {
        case .all: return .all
        case .ot: return .ot
        case .nt: return .nt
        case .currentBook: return .book(currentBook)
        }
    }
}

/// Origen de los resultados (la base de datos real o un doble en las pruebas).
public protocol SearchProviding: AnyObject {
    func page(query: String, translationId: String, scope: SearchRepository.Scope, limit: Int) throws -> SearchPage
    /// Coincidencias de la consulta en cada versión (para sugerir otra cuando no hay resultados).
    func counts(query: String, scope: SearchRepository.Scope, translationIds: [String]) -> [(id: String, count: Int)]
}

public final class RepositorySearchProvider: SearchProviding {
    private let repo: SearchRepository
    public init(db: BibleDatabase) { repo = SearchRepository(db: db) }
    public func page(query: String, translationId: String, scope: SearchRepository.Scope, limit: Int) throws -> SearchPage {
        try repo.page(query, translationId: translationId, scope: scope, limit: limit)
    }
    public func counts(query: String, scope: SearchRepository.Scope, translationIds: [String]) -> [(id: String, count: Int)] {
        translationIds.map { id in
            (id, (try? repo.page(query, translationId: id, scope: scope, limit: 1).total) ?? 0)
        }
    }
}

public struct SearchResults: Equatable {
    public var query: String
    public var terms: [String]
    public var translationId: String
    public var groups: [SearchGroup]
    public var total: Int
    public var loaded: Int
    public var hasMore: Bool { loaded < total }
    public var remaining: Int { max(0, total - loaded) }
    public var bookCount: Int { groups.count }
}

public enum SearchState: Equatable {
    case idle
    case loading
    case results(SearchResults)
    case empty(query: String, translationId: String, suggestion: SearchSuggestion?)
    case error(String)
}

/// Controlador de la búsqueda (S05) sin interfaz: debounce de la consulta, ejecución en una cola de fondo,
/// descarte de resultados obsoletos (un contador de generación; sin Swift Concurrency), historial y ⌘G.
/// Todas las propiedades y `onChange` se usan en `callbackQueue` (la principal en la app).
public final class SearchModel {
    public static let pageSize = 500

    public private(set) var state: SearchState = .idle
    public private(set) var query = ""
    public var translationId: String
    public var scopeChoice: SearchScopeChoice = .all
    public var currentBook = 43
    /// Versiones entre las que sugerir si no hay resultados.
    public var allTranslationIds: [String] = []
    public private(set) var activeHitId: String?
    public var onChange: (() -> Void)?

    private let provider: SearchProviding
    private let user: UserStore?
    private let work: DispatchQueue
    private let callback: DispatchQueue
    private let debounce: TimeInterval
    private var generation = 0
    private var pending: DispatchWorkItem?
    private var limit = SearchModel.pageSize

    public init(provider: SearchProviding, user: UserStore?, translationId: String,
                debounce: TimeInterval = 0.25,
                workQueue: DispatchQueue = DispatchQueue(label: "org.biblia.clasica.search", qos: .userInitiated),
                callbackQueue: DispatchQueue = .main) {
        self.provider = provider; self.user = user; self.translationId = translationId
        self.debounce = debounce; work = workQueue; callback = callbackQueue
    }

    public var terms: [String] { SearchTerms.split(query) }
    public var results: SearchResults? { if case .results(let r) = state { return r } else { return nil } }
    public var flatHits: [SearchHit] { results?.groups.flatMap(\.hits) ?? [] }
    public var isIdle: Bool { state == .idle }

    private func set(_ s: SearchState) { state = s; onChange?() }

    // MARK: consulta

    /// Cada pulsación: se espera `debounce` sin más cambios antes de buscar; vacío = vuelve al inicio.
    public func queryChanged(_ q: String) {
        query = q
        pending?.cancel()
        generation += 1                       // lo que esté en curso queda obsoleto
        guard !SearchTerms.split(q).isEmpty else { activeHitId = nil; set(.idle); return }
        let item = DispatchWorkItem { [weak self] in self?.start(keepResults: false) }
        pending = item
        callback.asyncAfter(deadline: .now() + debounce, execute: item)
    }

    /// Intro: busca ya y guarda la consulta en el historial.
    public func submit(_ q: String) {
        query = q
        pending?.cancel()
        guard !SearchTerms.split(q).isEmpty else { generation += 1; set(.idle); return }
        remember()
        start(keepResults: false)
    }

    public func setScope(_ c: SearchScopeChoice) { scopeChoice = c; rerun() }
    public func setTranslation(_ id: String) { translationId = id; rerun() }
    private func rerun() {
        pending?.cancel()
        if SearchTerms.split(query).isEmpty { return }
        start(keepResults: false)
    }

    public func loadMore() {
        guard results?.hasMore == true else { return }
        limit += SearchModel.pageSize
        start(keepResults: true)
    }

    private func start(keepResults: Bool) {
        pending = nil
        if !keepResults { limit = SearchModel.pageSize; activeHitId = nil }
        generation += 1
        let gen = generation
        let q = query, tid = translationId, scope = scopeChoice.scope(currentBook: currentBook)
        let lim = limit, others = allTranslationIds
        if !keepResults { set(.loading) }
        work.async { [weak self] in
            guard let self = self else { return }
            var outcome: SearchState
            do {
                let page = try self.provider.page(query: q, translationId: tid, scope: scope, limit: lim)
                if page.total == 0 {
                    let sug = SearchSuggestion.best(counts: self.provider.counts(query: q, scope: scope, translationIds: others), excluding: tid)
                    outcome = .empty(query: q, translationId: tid, suggestion: sug)
                } else {
                    outcome = .results(SearchResults(query: q, terms: SearchTerms.split(q), translationId: tid,
                                                     groups: SearchGrouping.group(page.hits, totals: page.perBook),
                                                     total: page.total, loaded: page.hits.count))
                }
            } catch {
                outcome = .error("No se pudo buscar: \(error.localizedDescription)")
            }
            self.callback.async { [weak self] in
                guard let self = self, self.generation == gen else { return }   // obsoleto: se descarta
                self.set(outcome)
            }
        }
    }

    // MARK: ⌘G / ⇧⌘G

    public func markActive(_ hit: SearchHit) { activeHitId = hit.id }

    /// Resultado siguiente (+1) o anterior (-1) al último abierto; el primero/último si aún no se abrió ninguno.
    /// `nil` al llegar a un extremo.
    public func advance(_ delta: Int) -> SearchHit? {
        let hits = flatHits
        guard !hits.isEmpty else { return nil }
        let next: Int
        if let id = activeHitId, let i = hits.firstIndex(where: { $0.id == id }) { next = i + delta }
        else { next = delta >= 0 ? 0 : hits.count - 1 }
        guard hits.indices.contains(next) else { return nil }
        activeHitId = hits[next].id
        return hits[next]
    }

    // MARK: historial

    public func remember() {
        try? user?.addSearch(query)
    }
    public func recentQueries() -> [String] { (try? user?.recentSearches(limit: UserStore.maxSearches)) ?? [] }
    public func clearHistory() { try? user?.clearSearches() }
}

/// Fila de la lista de resultados (cabecera de libro, resultado, «Mostrar más»).
public enum SearchRow: Equatable {
    case header(book: Int, count: Int)
    case hit(SearchHit)
    case more(remaining: Int)

    public static func rows(_ r: SearchResults) -> [SearchRow] {
        var out: [SearchRow] = []
        for g in r.groups {
            out.append(.header(book: g.book, count: g.count))
            out.append(contentsOf: g.hits.map { .hit($0) })
        }
        if r.hasMore { out.append(.more(remaining: r.remaining)) }
        return out
    }
}

/// Fragmento del resultado con las coincidencias resaltadas.
public enum SearchSnippet {
    public static func attributed(_ hit: SearchHit, terms: [String], font: NSFont, color: NSColor,
                                  matchBackground: NSColor, matchColor: NSColor, maxLength: Int = 150) -> NSAttributedString {
        let text = SearchHighlighter.window(hit.text.isEmpty ? hit.snippet : hit.text, terms: terms, maxLength: maxLength)
        let out = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        let bold = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        for r in SearchHighlighter.ranges(in: text, terms: terms) {
            out.addAttributes([.backgroundColor: matchBackground, .foregroundColor: matchColor, .font: bold], range: NSRange(r, in: text))
        }
        return out
    }
}
