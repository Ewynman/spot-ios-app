//
//  PostComposerPhoto.swift
//  Spot
//
//  Stable identity for composer photos so SwiftUI lists / TabView pages don’t
//  reuse the wrong view when reordering or replacing images.
//

import UIKit

struct PostComposerPhoto: Identifiable {
    let id: UUID
    var image: UIImage

    init(id: UUID = UUID(), image: UIImage) {
        self.id = id
        self.image = image
    }
}

extension PostComposerPhoto: Equatable {
    static func == (lhs: PostComposerPhoto, rhs: PostComposerPhoto) -> Bool {
        lhs.id == rhs.id && lhs.image === rhs.image
    }
}
