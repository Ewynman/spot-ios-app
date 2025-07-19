import SwiftUI
import MapKit

struct ProfileView: View {
    @StateObject private var viewModel: ProfileViewModel
    @State private var selectedTab = "Spots"
    @State private var showMenu = false
    private let tabs = ["Spots", "Map"]
    let userId: String? // nil means current user's profile
    
    init(userId: String? = nil) {
        self.userId = userId
        self._viewModel = StateObject(wrappedValue: userId == nil ? ProfileViewModel.previewViewModel : ProfileViewModel())
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Top Navigation
            HStack {
                Text("Spot")
                    .font(FontManager.logoTitle())
                    .foregroundColor(Constants.Colors.primary)
                
                Spacer()
                
                if userId == nil {
                    Menu {
                        Button(action: {
                            // Navigate to Likes
                        }) {
                            Label("Your Likes", systemImage: "heart.fill")
                        }
                        
                        Button(action: {
                            // Navigate to Bookmarks
                        }) {
                            Label("Bookmarks", systemImage: "bookmark.fill")
                        }
                        
                        Button(action: {
                            // Navigate to Settings
                        }) {
                            Label("Settings", systemImage: "gearshape.fill")
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 20))
                            .foregroundColor(Constants.Colors.primary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            
            if let user = viewModel.user {
                // Profile Header
                VStack(spacing: 16) {
                    // Profile Image
                    if let imageURL = user.profileImageURL {
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
                    
                    // Username and Spots Count
                    VStack(spacing: 4) {
                        Text(user.username)
                            .font(FontManager.sectionHeader())
                            .foregroundColor(.black)
                        
                        Text("\(viewModel.spots.count) spots shared")
                            .font(FontManager.primaryText())
                            .foregroundColor(.gray)
                    }
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
                    SpotsGridView(spots: viewModel.spots)
                        .padding(.top, 1)
                } else {
                    ProfileMapView(spots: viewModel.spots)
                }
                
                Spacer()
            } else if viewModel.isLoading {
                LoadingView()
            } else if viewModel.error != nil {
                ErrorView(error: viewModel.error!)
            }
        }
        .background(Color(hex: "F5F3EF"))
        .onAppear {
            viewModel.loadUserProfile(userId: userId)
            viewModel.loadUserSpots(userId: userId)
        }
    }
}

struct ProfileHeaderView: View {
    let user: User
    
    var body: some View {
        VStack(spacing: 16) {
            // Profile Image
            if let imageURL = user.profileImageURL {
                AsyncImage(url: URL(string: imageURL)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                }
                .frame(width: 80, height: 80)
                .clipShape(Circle())
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .frame(width: 80, height: 80)
                    .foregroundColor(.gray)
            }
            
            // Username
            Text(user.username)
                .font(FontManager.sectionHeader())
                .foregroundColor(.black)
            
            // Private Profile Badge
            if user.isPrivate {
                HStack {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12))
                    Text("Private Profile")
                        .font(FontManager.primaryText())
                }
                .foregroundColor(.gray)
            }
        }
        .padding(.horizontal, 16)
    }
}

struct ProfileStatsView: View {
    let spots: [Spot]
    
    var body: some View {
        HStack(spacing: 32) {
            StatItem(value: spots.count, label: "Spots")
            StatItem(value: spots.filter { $0.isLiked ?? false }.count, label: "Liked")
            StatItem(value: spots.filter { $0.isSaved ?? false }.count, label: "Saved")
        }
        .padding(.horizontal, 16)
    }
}

struct StatItem: View {
    let value: Int
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(FontManager.sectionHeader())
                .foregroundColor(Constants.Colors.primary)
            Text(label)
                .font(FontManager.primaryText())
                .foregroundColor(.gray)
        }
    }
}

struct ErrorView: View {
    let error: Error
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.red)
            Text(error.localizedDescription)
                .font(FontManager.primaryText())
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

struct SpotsGridView: View {
    let spots: [Spot]
    let columns = [
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1)
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 1) {
                ForEach(spots) { spot in
                    SpotGridItem(spot: spot)
                }
            }
        }
        .background(Color(hex: "F5F3EF"))
    }
}

struct SpotGridItem: View {
    let spot: Spot
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Spot Image
            AsyncImage(url: URL(string: spot.imageURL ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(
                RoundedCorner(radius: 12, corners: [.topLeft, .topRight])
            )
            
            // Location Name
            Text(spot.locationName ?? "")
                .font(FontManager.primaryText())
                .foregroundColor(.white)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Constants.Colors.primary)
                .clipShape(
                    RoundedCorner(radius: 12, corners: [.bottomLeft, .bottomRight])
                )
        }
        .padding(4)
    }
}

// Custom shape for specific corner rounding
struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

struct ProfileMapView: View {
    let spots: [Spot]
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 25.7617, longitude: -80.1918),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    
    var body: some View {
        if #available(iOS 17.0, *) {
            Map(
                coordinateRegion: $region,
                annotationItems: spots.map { SpotAnnotation(spot: $0) }
            ) { annotation in
                MapAnnotation(coordinate: annotation.coordinate) {
                    SpotMapMarker(spot: annotation.spot)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
        } else {
            Map(
                coordinateRegion: $region,
                annotationItems: spots.map { SpotAnnotation(spot: $0) }
            ) { annotation in
                MapAnnotation(coordinate: annotation.coordinate) {
                    SpotMapMarker(spot: annotation.spot)
                }
            }
        }
    }
}

// MARK: - Previews
//struct ProfileView_Previews: PreviewProvider {
//    static var previews: some View {
//        Group {
//            // Current User Profile
//            ProfileView()
//                .previewDisplayName("Current User")
//            
//            // Other User Profile (with data)
//            ProfileView(userId: "other123")
//                .environmentObject(ProfileViewModel.previewOtherUserViewModel)
//                .previewDisplayName("Other User")
//            
//            // Private Profile
//            ProfileView(userId: "private123")
//                .environmentObject(ProfileViewModel.previewPrivateViewModel)
//                .previewDisplayName("Private Profile")
//            
//            // Empty Profile
//            ProfileView(userId: "empty123")
//                .environmentObject(ProfileViewModel.previewEmptyViewModel)
//                .previewDisplayName("Empty Profile")
//        }
//    }
//} 
