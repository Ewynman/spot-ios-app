import SwiftUI
import FirebaseFirestore

struct UserProfileView: View {
    let userId: String
    @State private var username: String = ""
    @State private var profileImageURL: String?
    @State private var spots: [Spot] = []
    @State private var selectedTab = "Spots"
    @State private var selectedSpot: Spot?
    @State private var isLoading = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.presentationMode) private var presentationMode
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
                if selectedSpot != nil {
                    Button(action: { selectedSpot = nil }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Back to all spots")
                                .font(FontManager.primaryText())
                        }
                        .foregroundColor(Constants.Colors.primary)
                    }
                } else {
                    CustomBackButton(action: { dismiss() })
                }
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
                if selectedSpot == nil {
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
                } else {
                    // Show selected spot detail
                    ScrollView {
                        VStack(spacing: 0) {
                            // Spot Image - Full width
                            if let imageURL = selectedSpot?.imageURL {
                                AsyncImage(url: URL(string: imageURL)) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(maxWidth: .infinity, maxHeight: 500) // Slightly larger for detail view
                                } placeholder: {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(maxWidth: .infinity, maxHeight: 500)
                                }
                            }
                            
                            // Location info - Match grid styling
                            if let locationName = selectedSpot?.locationName {
                                HStack {
                                    Image(systemName: "mappin.circle.fill")
                                        .foregroundColor(Constants.Colors.primary)
                                    Text(locationName)
                                        .font(FontManager.primaryText())
                                        .foregroundColor(Constants.Colors.primary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            }
                            
                            // Interaction Bar
                            HStack {
                                HStack(spacing: 16) {
                                    Button(action: {
                                        // Toggle like - Add actual functionality
                                        if let spot = selectedSpot {
                                            var updatedSpot = spot
                                            updatedSpot.isLiked = !(spot.isLiked ?? false)
                                            selectedSpot = updatedSpot
                                        }
                                    }) {
                                        Image(systemName: selectedSpot?.isLiked ?? false ? "heart.fill" : "heart")
                                            .foregroundColor(selectedSpot?.isLiked ?? false ? .red : .gray)
                                            .font(.system(size: 22))
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    
                                    Button(action: {
                                        // Toggle save - Add actual functionality
                                        if let spot = selectedSpot {
                                            var updatedSpot = spot
                                            updatedSpot.isSaved = !(spot.isSaved ?? false)
                                            selectedSpot = updatedSpot
                                        }
                                    }) {
                                        Image(systemName: selectedSpot?.isSaved ?? false ? "bookmark.fill" : "bookmark")
                                            .foregroundColor(selectedSpot?.isSaved ?? false ? Constants.Colors.primary : .gray)
                                            .font(.system(size: 22))
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                                
                                Spacer()
                                
                                if let vibe = selectedSpot?.vibeTag {
                                    Text(vibe)
                                        .font(FontManager.primaryText())
                                        .foregroundColor(Constants.Colors.primary)
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 12)
                                        .background(Constants.Colors.accent)
                                        .cornerRadius(12)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                    }
                }
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
