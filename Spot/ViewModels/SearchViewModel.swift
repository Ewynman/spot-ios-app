import Foundation
import FirebaseFirestore
@MainActor
final class SearchViewModel: ObservableObject {
    enum Segment: String, CaseIterable { case users = "Users", locations = "Locations", vibes = "Vibes" }

    @Published var query: String = "" {
        didSet {
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
            SpotLogger.debug("Search query changed", details: ["query": q])
            debouncer.schedule { Task { await self.performSearch() } }
        }
    }
    @Published var segment: Segment = .users {
        didSet {
            SpotLogger.info("Search segment switched", details: ["segment": segment.rawValue])
            // Clear current results and any open grid when switching tabs
            users = []
            locations = []
            vibes = []
            gridTitle = nil
            gridIsVibe = false
            gridSpots = []
            lastGridDoc = nil
            hasMoreGrid = true
            Task { await self.performSearch(force: true) }
        }
    }

    // Sections
    @Published var users: [[String: Any]] = []
    @Published var locations: [String] = []
    @Published var vibes: [String] = []

    // Grids
    @Published var gridTitle: String?
    @Published var gridIsVibe: Bool = false
    @Published var gridSpots: [Spot] = []
    private var lastGridDoc: DocumentSnapshot?
    @Published var isLoadingGrid = false
    @Published var hasMoreGrid = true

    private let debouncer = Debouncer(interval: 0.3)
    private let service = SearchService.shared

    func clear() {
        users = []; locations = []; vibes = []
    }

    func performSearch(force: Bool = false) async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { clear(); return }

        switch segment {
        case .users:
            do {
                users = try await service.searchUsers(prefix: q).items
                SpotLogger.info("Search users results", details: ["count": users.count])
            } catch { }
        case .locations:
            do {
                locations = try await service.searchLocationSuggestions(prefix: q)
                SpotLogger.info("Search locations suggestions", details: ["count": locations.count])
            } catch { }
        case .vibes:
            do {
                vibes = try await service.searchVibeSuggestions(prefix: q)
                SpotLogger.info("Search vibes suggestions", details: ["count": vibes.count])
            } catch { }
        }
    }

    // MARK: Grid flows
    func openLocation(_ name: String) async {
        gridTitle = name
        gridIsVibe = false
        // Clear suggestions so only the grid is visible
        users = []
        locations = []
        vibes = []
        gridSpots = []
        lastGridDoc = nil
        hasMoreGrid = true
        SpotLogger.debug("Open location grid", details: ["name": name])
        await loadMoreGrid()
    }

    func openVibe(_ tag: String) async {
        gridTitle = tag
        gridIsVibe = true
        users = []
        locations = []
        vibes = []
        gridSpots = []
        lastGridDoc = nil
        hasMoreGrid = true
        SpotLogger.debug("Open vibe grid", details: ["tag": tag])
        await loadMoreGrid(isVibe: true)
    }

    func loadMoreGrid(isVibe: Bool = false) async {
        guard !isLoadingGrid, hasMoreGrid, let title = gridTitle else { return }
        isLoadingGrid = true
        defer { isLoadingGrid = false }
        do {
            let lower = title.lowercased()
            var accumulated: [Spot] = []
            var attempts = 0
            var nextCursor = lastGridDoc
            var set = Set(gridSpots.compactMap { $0.id })
            while accumulated.count < 24 && attempts < 5 {
                attempts += 1
                let page = try await (isVibe ? service.fetchSpotsByVibe(lower, last: nextCursor) : service.fetchSpotsByLocation(lower, last: nextCursor))
                nextCursor = page.lastDocument
                let newUnique = page.items.filter { spot in
                    let id = spot.id ?? UUID().uuidString
                    if set.contains(id) { return false }
                    set.insert(id)
                    return true
                }
                accumulated.append(contentsOf: newUnique)
                if page.items.isEmpty || nextCursor == nil { break }
            }
            gridSpots.append(contentsOf: accumulated)
            lastGridDoc = nextCursor
            hasMoreGrid = !(accumulated.isEmpty && nextCursor == nil)
            SpotLogger.info("Grid loaded page", details: [
                "pageCount": accumulated.count,
                "total": gridSpots.count,
                "hasMore": hasMoreGrid
            ])
        } catch {
            hasMoreGrid = false
            SpotLogger.error("Grid load failed", details: ["error": error.localizedDescription])
        }
    }
}
