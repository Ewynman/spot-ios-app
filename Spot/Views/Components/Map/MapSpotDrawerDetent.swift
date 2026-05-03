//
//  MapSpotDrawerDetent.swift
//  Spot
//
//  Peek vs expanded height for the discovery map spot preview drawer.
//

import Foundation

enum MapSpotDrawerDetent: String, Equatable, Sendable {
    /// Shorter panel (viewport clamp); map stays visible.
    case peek
    /// Raised toward full height so details are visible with minimal scroll.
    case expanded
}
