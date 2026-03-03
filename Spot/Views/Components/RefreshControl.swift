//
//  RefreshControl.swift
//  Spot
//
//  Created By: Wynman, Edward
//  Date: 03/02/2025
//

import SwiftUI

struct RefreshControl: View {
    let coordinateSpace: CoordinateSpace
    let onRefresh: () -> Void

    @State private var isRefreshing = false

    var body: some View {
        GeometryReader { geo in
            if geo.frame(in: coordinateSpace).midY > 50 {
                Spacer()
                    .onAppear {
                        if !isRefreshing {
                            isRefreshing = true
                            onRefresh()
                        }
                    }
            } else if geo.frame(in: coordinateSpace).midY < 0 {
                Spacer()
                    .onAppear {
                        isRefreshing = false
                    }
            }
            HStack {
                Spacer()
                if isRefreshing {
                    ProgressView()
                }
                Spacer()
            }
        }
        .padding(.top, -50)
    }
}
