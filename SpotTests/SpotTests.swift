//
//  SpotTests.swift
//  SpotTests
//
//  Created By: Wynman, Edward
//  Date: 03/02/2025
//

import Testing
@testable import Spot

/// Root test suite - individual logic tests live in GeoHashTests, StringNormalizerTests, etc.
struct SpotTests {

    @Test func spotModuleLoads() {
        #expect(GeoHash.encode(latitude: 0, longitude: 0, precision: 1).count == 1)
    }
}
