//
//  MainTabView.swift
//  Spot
//
//  Created By Wynman, Edward 03/02/2026
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var authVM: AuthViewModel

    var body: some View {
        BottomTabNavigationView()
    }
}

#Preview {
    let auth = AuthViewModel()
    auth.isAuthenticated = true
    return MainTabView().environmentObject(auth)
}
