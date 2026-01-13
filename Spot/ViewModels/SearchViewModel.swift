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
    // Advanced filters (Pro)
    @Published var allVibeTags: [String] = []
    @Published var selectedVibeFilters: Set<String> = []
    @Published var gridVibeFilters: [String]? // Published so view can display active filters
    private var gridLocationFilter: String? // Track location when filtering by vibes

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
        gridLocationFilter = name // Store location for potential vibe filtering
        gridVibeFilters = nil // Clear vibe filters when opening new location
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
        gridVibeFilters = nil
        SpotLogger.debug("Open vibe grid", details: ["tag": tag])
        await loadMoreGrid(isVibe: true)
    }

    func openVibeFilters(_ tags: [String]) async {
        guard !tags.isEmpty else { return }
        gridTitle = "Vibes"
        gridIsVibe = true
        users = []
        locations = []
        vibes = []
        gridSpots = []
        lastGridDoc = nil
        hasMoreGrid = true
        gridVibeFilters = tags
        SpotLogger.debug("Open multi-vibe grid", details: ["count": tags.count])
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
                let page: SearchPage<Spot>
                // Check for location + vibe combination (Pro feature)
                if let locationFilter = gridLocationFilter, let filters = gridVibeFilters, !filters.isEmpty {
                    page = try await service.fetchSpotsByLocationAndVibes(locationFilter.lowercased(), vibeLowers: filters.map { $0.lowercased() }, last: nextCursor)
                } else if isVibe, let filters = gridVibeFilters, !filters.isEmpty {
                    page = try await service.fetchSpotsByVibes(filters.map { $0.lowercased() }, last: nextCursor)
                } else {
                    page = try await (isVibe ? service.fetchSpotsByVibe(lower, last: nextCursor) : service.fetchSpotsByLocation(lower, last: nextCursor))
                }
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

    // MARK: Vibe tags source for filters
    func loadAllVibeTags() async {
        // Fetch custom tags from database
        let customTags = await VibeTagService.shared.fetchAll().map { $0.name }
        
        // Combine defaults + custom tags, remove duplicates, and sort
        let allTags = Array(Set(Constants.VibeTags.defaultTags + customTags)).sorted { $0.lowercased() < $1.lowercased() }
        allVibeTags = allTags
        SpotLogger.info("Loaded all vibe tags for filters", details: ["defaultCount": Constants.VibeTags.defaultTags.count, "customCount": customTags.count, "total": allTags.count])
    }

    func applySelectedVibeFilters() async {
        let tags = Array(selectedVibeFilters)
        // If we have a location filter active, preserve it and filter by vibes within that location
        if let locationFilter = gridLocationFilter, !tags.isEmpty {
            gridVibeFilters = tags
            gridSpots = []
            lastGridDoc = nil
            hasMoreGrid = true
            SpotLogger.debug("Apply vibe filters to location", details: ["location": locationFilter, "vibes": tags])
            await loadMoreGrid(isVibe: false) // Not a pure vibe grid, but uses location+vibe combo
        } else if !tags.isEmpty {
            await openVibeFilters(tags)
        } else {
            // No tags selected, clear filters
            await clearFiltersAndReload()
        }
    }

    func clearFiltersAndReload() async {
        selectedVibeFilters.removeAll()
        gridVibeFilters = nil
        
        // If we have a location filter active, reload without vibe filters
        if let locationFilter = gridLocationFilter {
            gridSpots = []
            lastGridDoc = nil
            hasMoreGrid = true
            SpotLogger.debug("Clear vibe filters, reloading location", details: ["location": locationFilter])
            await loadMoreGrid(isVibe: false)
        } else if gridIsVibe, let title = gridTitle {
            // If we're viewing a vibe grid, reload without multi-vibe filters
            gridSpots = []
            lastGridDoc = nil
            hasMoreGrid = true
            SpotLogger.debug("Clear filters, reloading vibe", details: ["vibe": title])
            await loadMoreGrid(isVibe: true)
        }
        // Otherwise, grid will remain as-is (no filters were active)
    }
}
