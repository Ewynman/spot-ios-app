//
//  BlockedUsersView.swift
//  Spot
//
//  Created by Assistant on 8/14/25.
//

import SwiftUI
import FirebaseFirestore

struct BlockedUsersView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var blockedUserDetails: [BlockedUserInfo] = []
    @State private var isLoading = true
    @State private var showUnblockConfirm = false
    @State private var userToUnblock: BlockedUserInfo?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    Spacer()
                    ProgressView("Loading blocked users...")
                    Spacer()
                } else if blockedUserDetails.isEmpty {
                    emptyStateView
                } else {
                    blockedUsersList
                }
            }
            .navigationTitle("Blocked Users")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(Constants.Colors.primary)
                    }
                }
            }
            .background(Color(hex: "F5F3EF"))
        }
        .onAppear {
            loadBlockedUsers()
        }
        .alert("Unblock User", isPresented: $showUnblockConfirm) {
            Button("Unblock", role: .destructive) {
                if let user = userToUnblock {
                    Task { await unblockUser(user) }
                }
            }
            Button("Cancel", role: .cancel) {
                userToUnblock = nil
            }
        } message: {
            if let user = userToUnblock {
                Text("Are you sure you want to unblock @\(user.username)?")
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "person.slash")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Blocked Users")
                .font(FontManager.sectionHeader())
                .foregroundColor(Constants.Colors.primary)
            
            Text("You haven't blocked anyone.")
                .font(FontManager.primaryText())
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            
            Spacer()
        }
        .background(Color(hex: "F5F3EF"))
    }
    
    private var blockedUsersList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(blockedUserDetails) { user in
                    blockedUserRow(user)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .background(Color(hex: "F5F3EF"))
    }
    
    private func blockedUserRow(_ user: BlockedUserInfo) -> some View {
        HStack(spacing: 12) {
            // Profile image
            if let urlString = user.profileImageURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { img in
                    img.resizable()
                       .aspectRatio(contentMode: .fill)
                       .frame(width: 50, height: 50)
                       .clipShape(Circle())
                } placeholder: {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 50, height: 50)
                        .overlay(
                            Image(systemName: "person.fill")
                                .foregroundColor(.gray)
                        )
                }
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Image(systemName: "person.fill")
                            .foregroundColor(.gray)
                    )
            }
            
            // Username
            VStack(alignment: .leading, spacing: 4) {
                Text("@\(user.username)")
                    .font(FontManager.primaryText())
                    .fontWeight(.semibold)
                    .foregroundColor(Constants.Colors.primary)
                
                Text("Blocked")
                    .font(FontManager.primaryText())
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            // Unblock button
            Button {
                userToUnblock = user
                showUnblockConfirm = true
            } label: {
                Text("Unblock")
                    .font(FontManager.primaryText())
                    .foregroundColor(Constants.Colors.buttonText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Constants.Colors.primary)
                    .cornerRadius(20)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(16)
        .background(Constants.Colors.background)
        .cornerRadius(12)
    }
    
    private func loadBlockedUsers() {
        isLoading = true
        Task {
            do {
                var userDetails: [BlockedUserInfo] = []
                
                for userId in authVM.blockedUsers {
                    let userDoc = try await Firestore.firestore().collection("users").document(userId).getDocument()
                    if let data = userDoc.data() {
                        let username = data["username"] as? String ?? "Unknown"
                        let profileImageURL = data["profileImageURL"] as? String
                        userDetails.append(BlockedUserInfo(
                            id: userId,
                            username: username,
                            profileImageURL: profileImageURL
                        ))
                    }
                }
                
                await MainActor.run {
                    self.blockedUserDetails = userDetails
                    self.isLoading = false
                }
            } catch {
                SpotLogger.error("Failed to load blocked user details: \(error.localizedDescription)")
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
    
    @MainActor
    private func unblockUser(_ user: BlockedUserInfo) async {
        do {
            try await authVM.unblockUser(userId: user.id)
            blockedUserDetails.removeAll { $0.id == user.id }
            userToUnblock = nil
            SpotLogger.info("User unblocked from settings: \(user.id)")
        } catch {
            SpotLogger.error("Failed to unblock user: \(error.localizedDescription)")
            userToUnblock = nil
        }
    }
}

struct BlockedUserInfo: Identifiable {
    let id: String
    let username: String
    let profileImageURL: String?
}
