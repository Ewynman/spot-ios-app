//
//  Spot+Extensions.swift
//  Spot
//
//  Created by Edward Wynman on 1/12/26.
//

import Foundation

extension Spot {
    /// Safe ID that returns the spot's ID or "nil" if the ID is nil
    var safeId: String {
        return id ?? "nil"
    }
}