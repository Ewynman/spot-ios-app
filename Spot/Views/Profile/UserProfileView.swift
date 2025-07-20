import SwiftUI
import FirebaseFirestore

struct UserProfileView: View {
    let userId: String
    @State private var username: String = ""
    @State private var profileImageURL: String?
    @State private var spots: [Spot] = []
    @State private var selectedTab = "Spots"
    @State private var isLoading = false
    @Environment(\.dismiss) private var dismiss
    private let tabs = ["Spots", "Map"]
    
    var body: some View {
        VStack(spacing: 0) {
            // SPOT Logo
            Text("SPOT")
                .font(FontManager.logoTitle())
                .foregroundColor(Constants.Colors.primary)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            
            // Back Button
            HStack {
                CustomBackButton(action: { dismiss() })
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            
            if isLoading {
                Spacer()
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                Spacer()
            } else {
                // Profile Header
                VStack(spacing: 16) {
                    // Profile Image
                    if let imageURL = profileImageURL {
                        AsyncImage(url: URL(string: imageURL)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Image(systemName: "person.circle.fill")
                                .resizable()
                                .foregroundColor(.gray)
                        }
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                    } else {
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .frame(width: 100, height: 100)
                            .foregroundColor(.gray)
                    }
                    
                    // Username
                    Text(username)
                        .font(FontManager.sectionHeader())
                        .foregroundColor(.black)
                    
                    // Spots Count
                    Text("\(spots.count) spots shared")
                        .font(FontManager.primaryText())
                        .foregroundColor(.gray)
                }
                .padding(.top, 16)
                
                // Tab Navigation
                VStack(spacing: 0) {
                    HStack(spacing: 32) {
                        ForEach(tabs, id: \.self) { tab in
                            VStack(spacing: 4) {
                                Text(tab)
                                    .font(FontManager.primaryText())
                                    .fontWeight(selectedTab == tab ? .semibold : .regular)
                                    .foregroundColor(selectedTab == tab ? Constants.Colors.primary : .gray)
                                
                                Rectangle()
                                    .fill(selectedTab == tab ? Constants.Colors.primary : Color.clear)
                                    .frame(height: 2)
                            }
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedTab = tab
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.top, 24)
                
                // Content
                if selectedTab == "Spots" {
                    if spots.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.gray)
                            Text("No spots shared yet")
                                .font(FontManager.primaryText())
                                .foregroundColor(.gray)
                        }
                        .padding(.top, 40)
                    } else {
                        SpotsGridView(spots: spots)
                            .padding(.top, 1)
                    }
                } else {
                    ProfileMapView(spots: spots)
                }
                
                Spacer()
            }
            
            // Bottom Navigation
            BottomNavigationView(selectedTab: .constant("Home"))
        }
        .background(Color(hex: "F5F3EF"))
        .onAppear {
            loadUserData()
        }
    }
    
    private func loadUserData() {
        isLoading = true
        
        Task {
            do {
                SpotLogger.debug("Loading profile for user: \(userId)")
                
                // Load user data
                let userDoc = try await Firestore.firestore()
                    .collection("users")
                    .document(userId)
                    .getDocument()
                
                guard let data = userDoc.data() else {
                    SpotLogger.error("No user data found for ID: \(userId)")
                    return
                }
                
                // Update user info
                await MainActor.run {
                    username = data["username"] as? String ?? "User"
                    profileImageURL = data["profileImageURL"] as? String
                }
                
                SpotLogger.info("Loaded profile for user: \(username)")
                
                // Load user's spots
                let spotsSnapshot = try await Firestore.firestore()
                    .collection("spots")
                    .whereField("userId", isEqualTo: userId)
                    .order(by: "createdAt", descending: true)
                    .getDocuments()
                
                let userSpots = try await withThrowingTaskGroup(of: Spot?.self) { group in
                    for document in spotsSnapshot.documents {
                        group.addTask {
                            return try await Spot.fromDocument(document)
                        }
                    }
                    
                    var validSpots: [Spot] = []
                    for try await spot in group {
                        if let spot = spot {
                            validSpots.append(spot)
                        }
                    }
                    return validSpots
                }
                
                await MainActor.run {
                    spots = userSpots
                    isLoading = false
                }
                
                SpotLogger.info("Loaded \(userSpots.count) spots for user: \(userId)")
            } catch {
                SpotLogger.error("Failed to load user data: \(error.localizedDescription)")
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }
} 