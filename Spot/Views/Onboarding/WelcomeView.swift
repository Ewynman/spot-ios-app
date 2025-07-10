//
//  WelcomeView.swift
//  Spot
//
//  Created by Edward Wynman on 7/10/25.
//

import SwiftUI

struct WelcomeView: View {
    @State private var navigateToNext = false
    @State private var showLogin = false

    var body: some View {
        NavigationStack {
            ZStack {
                Image("welcome_background")
                    .resizable()
                    .scaledToFill()
                    .edgesIgnoringSafeArea(.all)

                VStack {
                    VStack(spacing: 8) {
                        Text("SPOT")
                            .font(Constants.Fonts.title())
                            .foregroundColor(Color(hex: "#2D4A3D"))

                        Text("Your Favorite Places Shared")
                            .font(Constants.Fonts.body())
                            .foregroundColor(Color(hex: "#2D4A3D"))
                    }
                    .padding(.top, 60)

                    Spacer()

                    Button(action: {
                        navigateToNext = true
                    }) {
                        Text("Get Started")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(hex:"#3F7F5F"))
                            .foregroundColor(.white)
                            .cornerRadius(40)
                            .padding(.horizontal, 32)
                    }

                    HStack {
                        Text("Already have an account?")
                            .font(Constants.Fonts.small())
                            .foregroundColor(.white)

                        Button("Login") {
                            showLogin = true
                        }
                        .font(Constants.Fonts.small())
                        .fontWeight(.black)
                        .foregroundColor(.white)
                        .underline()
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 24)

                    NavigationLink(destination: LocationPermissionView(), isActive: $navigateToNext) {
                        EmptyView()
                    }
                    .hidden()

                    NavigationLink(destination: LoginView(), isActive: $showLogin) {
                        EmptyView()
                    }
                    .hidden()
                }
            }
        }
    }
}


#Preview {
    WelcomeView()
}
