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

    /// Fields that can change after a feed refresh while `id` stays the same (likes, media, saves).
    /// Used so `SpotCard` can sync `@State currentSpot` from the parent `spot` when SwiftUI reuses the row.
    var feedRowSyncToken: String {
        "\(safeId)|\(imageURL ?? "")|\(likes ?? -1)|\(isLiked ?? false)|\(isSaved ?? false)|\(mediaCount ?? -1)"
    }
}