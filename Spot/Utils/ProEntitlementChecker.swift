//
//  ProEntitlementChecker.swift
//  Spot
//
//  Created By: Wynman, Edward
//  Date: 03/24/2026
//

import Foundation

/// Pure helper for deciding whether a StoreKit product ID counts as Spot Pro.
struct ProEntitlementChecker: Sendable {
    let proProductIDs: Set<String>

    init(proProductIDs: some Collection<String>) {
        self.proProductIDs = Set(proProductIDs)
    }

    func grantsPro(forProductID productID: String) -> Bool {
        proProductIDs.contains(productID)
    }
}
