//
//  HomeView.swift
//  Spot
//
//  Created by Edward Wynman on 7/10/25.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct HomeView: View {
    @State private var username: String = ""
    @State private var isLoading = true
   @State private var showUploadView = false
    var body: some View {
        NavigationStack {
            ZStack {
                Constants.Colors.background.ignoresSafeArea()

                if isLoading {
                    ProgressView()
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Welcome, \(username) 👋")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "#2D4A3D"))
                            .padding(.horizontal)

                        Text("This is your feed!")
                            .font(.system(size: 16, design: .rounded))
                            .foregroundColor(.gray)
                            .padding(.horizontal)

                        Spacer()
                        // Upload Spot Button
                        Button(action: {
                            showUploadView = true
                        }) {
                            Text("Post a Spot")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color(hex: "#3F7F5F"))
                                .cornerRadius(20)
                                .padding(.horizontal)
                        }

                        NavigationLink(destination: SpotUploadView(), isActive: $showUploadView) {
                            EmptyView()
                        }
                    }
                }
            }
            .onAppear {
                fetchUsername()
            }
        }
    }

    private func fetchUsername() {
        guard let uid = Auth.auth().currentUser?.uid else {
            self.username = "Guest"
            self.isLoading = false
            return
        }

        Firestore.firestore().collection("users").document(uid).getDocument { snapshot, error in
            if let data = snapshot?.data(), let name = data["username"] as? String {
                self.username = name
            } else {
                self.username = "User"
            }
            self.isLoading = false
        }
    }
}

#Preview {
    HomeView()
}
