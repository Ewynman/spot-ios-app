//
//  SearchViewModelStateTests.swift
//  SpotTests
//
//  Created By: Wynman, Edward
//  Date: 04/27/2026
//
//  Pure state-transition coverage for SearchViewModel.
//
//  SearchViewModel is welded to `SearchService.shared` and triggers a
//  debounced async `performSearch()` on `query`/`segment` mutations, so
//  these tests deliberately avoid mutating those fields. They guard
//  initial state, manual reset paths, and filter-list mutations that do
//  not initiate network calls.
//

import Foundation
import Testing
@testable import Spot

@MainActor
struct SearchViewModelStateTests {

    @Test func defaultStateIsEmpty() {
        let vm = SearchViewModel()
        #expect(vm.query == "")
        #expect(vm.segment == .users)
        #expect(vm.users.isEmpty)
        #expect(vm.locations.isEmpty)
        #expect(vm.vibes.isEmpty)
        #expect(vm.gridTitle == nil)
        #expect(vm.gridIsVibe == false)
        #expect(vm.gridSpots.isEmpty)
        #expect(vm.isLoadingGrid == false)
        #expect(vm.hasMoreGrid == true)
        #expect(vm.allVibeTags.isEmpty)
        #expect(vm.selectedVibeFilters.isEmpty)
        #expect(vm.gridVibeFilters == nil)
    }

    @Test func clearResetsEverySection() {
        let vm = SearchViewModel()
        vm.users = [["id": "u1"]]
        vm.locations = ["NYC"]
        vm.vibes = ["Chill"]
        vm.gridTitle = "NYC"
        vm.gridIsVibe = true
        vm.gridSpots = [SpotTestHelpers.makeSpot(id: "g1")]
        vm.gridVibeFilters = ["Chill"]
        vm.selectedVibeFilters = ["Chill"]
        vm.hasMoreGrid = false

        vm.clear()

        #expect(vm.users.isEmpty)
        #expect(vm.locations.isEmpty)
        #expect(vm.vibes.isEmpty)
        #expect(vm.gridTitle == nil)
        #expect(vm.gridIsVibe == false)
        #expect(vm.gridSpots.isEmpty)
        #expect(vm.gridVibeFilters == nil)
        #expect(vm.selectedVibeFilters.isEmpty)
        #expect(vm.hasMoreGrid == true)
    }

    @Test func segmentEnumExposesUsersLocationsVibes() {
        let cases = SearchViewModel.Segment.allCases
        #expect(cases.contains(.users))
        #expect(cases.contains(.locations))
        #expect(cases.contains(.vibes))
        #expect(SearchViewModel.Segment.users.rawValue == "Users")
        #expect(SearchViewModel.Segment.locations.rawValue == "Locations")
        #expect(SearchViewModel.Segment.vibes.rawValue == "Vibes")
    }

    @Test func selectedVibeFiltersAreMutable() {
        let vm = SearchViewModel()
        vm.selectedVibeFilters.insert("Chill")
        vm.selectedVibeFilters.insert("Adventure")
        #expect(vm.selectedVibeFilters == ["Chill", "Adventure"])
        vm.selectedVibeFilters.remove("Chill")
        #expect(vm.selectedVibeFilters == ["Adventure"])
    }

    @Test func clearFiltersAndReloadIsNoopWhenNoActiveGrid() async {
        let vm = SearchViewModel()
        vm.selectedVibeFilters = ["Chill"]
        vm.gridVibeFilters = ["Chill"]
        // No location filter, no gridIsVibe true → nothing to reload.
        await vm.clearFiltersAndReload()
        #expect(vm.selectedVibeFilters.isEmpty)
        #expect(vm.gridVibeFilters == nil)
        #expect(vm.gridSpots.isEmpty)
    }

    @Test func applySelectedVibeFiltersWithEmptySetClearsFilters() async {
        let vm = SearchViewModel()
        vm.gridVibeFilters = ["Chill"]
        // No location filter, no spots → safe to call without networking.
        await vm.applySelectedVibeFilters()
        #expect(vm.selectedVibeFilters.isEmpty)
        #expect(vm.gridVibeFilters == nil)
    }
}
