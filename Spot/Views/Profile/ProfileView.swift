import SwiftUI
import MapKit

struct ProfileView: View {
    @StateObject private var viewModel: ProfileViewModel
    @State private var selectedTab = "Spots"
    @State private var showMenu = false
    private let tabs = ["Spots", "Map"]
    
    init() {
        self._viewModel = StateObject(wrappedValue: ProfileViewModel())
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Top Navigation - Always show
            HStack {
                Text("Spot")
                    .font(FontManager.logoTitle())
                    .foregroundColor(Constants.Colors.primary)
                
                Spacer()
                
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
            .padding(.horizontal, 16)
            .padding(.top, 8)
            
            // Profile Content
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
                    
                    // Username
                    Text(user.username)
                        .font(FontManager.sectionHeader())
                        .foregroundColor(.black)
                    
                    // Spots Count
                    Text("\(viewModel.spots.count) spots shared")
                        .font(FontManager.primaryText())
                        .foregroundColor(.gray)
                }
                .padding(.top, 16)
                
                // Tab Navigation
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
                .padding(.top, 24)
                
                // Content
                if selectedTab == "Spots" {
                    SpotsGridView(spots: viewModel.spots)
                        .padding(.top, 1)
                } else {
                    ProfileMapView(spots: viewModel.spots)
                        .edgesIgnoringSafeArea(.horizontal)
                }
            } else {
                // Show loading state with proper structure
                VStack(spacing: 16) {
                    // Placeholder Profile Image
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .frame(width: 100, height: 100)
                        .foregroundColor(.gray)
                    
                    // Placeholder Username
                    Text("Loading...")
                        .font(FontManager.sectionHeader())
                        .foregroundColor(.gray)
                    
                    // Placeholder Spots Count
                    Text("0 spots shared")
                        .font(FontManager.primaryText())
                        .foregroundColor(.gray)
                }
                .padding(.top, 16)
                
                // Tab Navigation
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
                .padding(.top, 24)
                
                // Loading Content
                if selectedTab == "Spots" {
                    SpotsGridView(spots: [])
                        .padding(.top, 1)
                } else {
                    ProfileMapView(spots: [])
                        .edgesIgnoringSafeArea(.horizontal)
                }
            }
        }
        .background(Color(hex: "F5F3EF"))
        .onAppear {
            // Load data in background without blocking UI
            Task {
                await viewModel.loadUserProfile()
            }
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
    @State private var selectedSpot: Spot?
    
    var body: some View {
        GeometryReader { geometry in
            let sidePadding: CGFloat = 3
            let spacing: CGFloat = 5
            let availableWidth = geometry.size.width - (2 * sidePadding) - spacing
            let itemWidth = availableWidth / 2
            
            ScrollView {
                if let spot = selectedSpot {
                    // Selected Spot View - Same layout as grid but enlarged
                    VStack(spacing: 0) {
                        // Back Button
                        HStack {
                            Button(action: { 
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    selectedSpot = nil
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 16, weight: .semibold))
                                    Text("Back to all spots")
                                        .font(FontManager.primaryText())
                                }
                                .foregroundColor(Constants.Colors.primary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        
                        // Spot Image - Full width
                        if let imageURL = spot.imageURL {
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
                        if let locationName = spot.locationName {
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
                                    var updatedSpot = spot
                                    updatedSpot.isLiked = !(spot.isLiked ?? false)
                                    selectedSpot = updatedSpot
                                }) {
                                    Image(systemName: spot.isLiked ?? false ? "heart.fill" : "heart")
                                        .foregroundColor(spot.isLiked ?? false ? .red : .gray)
                                        .font(.system(size: 22))
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                Button(action: {
                                    // Toggle save - Add actual functionality
                                    var updatedSpot = spot
                                    updatedSpot.isSaved = !(spot.isSaved ?? false)
                                    selectedSpot = updatedSpot
                                }) {
                                    Image(systemName: spot.isSaved ?? false ? "bookmark.fill" : "bookmark")
                                        .foregroundColor(spot.isSaved ?? false ? Constants.Colors.primary : .gray)
                                        .font(.system(size: 22))
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            
                            Spacer()
                            
                            if let vibe = spot.vibeTag {
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
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .scale.combined(with: .opacity)
                    ))
                } else {
                    // Grid View
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: spacing),
                            GridItem(.flexible(), spacing: spacing)
                        ],
                        spacing: spacing
                    ) {
                        ForEach(spots) { spot in
                            SpotGridItem(spot: spot, width: itemWidth)
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        selectedSpot = spot
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, sidePadding)
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .scale.combined(with: .opacity)
                    ))
                }
            }
        }
    }
}

struct SpotGridItem: View {
    let spot: Spot
    let width: CGFloat
    
    var formattedLocation: String {
        guard let locationName = spot.locationName else { return "" }
        let components = locationName.split(separator: ",").map(String.init)
        if components.count >= 2 {
            let city = components[0].trimmingCharacters(in: .whitespaces)
            let state = components[1].trimmingCharacters(in: .whitespaces)
            return "\(city), \(state)"
        }
        return locationName
    }
    
    var imageHeight: CGFloat {
        return width // Keep square for grid but use fit content mode
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Spot Image
            if let imageURL = spot.imageURL, !imageURL.isEmpty {
                AsyncImage(url: URL(string: imageURL)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: width, height: imageHeight)
                            .background(Color.gray.opacity(0.1))
                            .clipShape(
                                .rect(
                                    topLeadingRadius: 12,
                                    bottomLeadingRadius: 0,
                                    bottomTrailingRadius: 0,
                                    topTrailingRadius: 12
                                )
                            )
                    case .failure(_):
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: width, height: imageHeight)
                            .clipShape(
                                .rect(
                                    topLeadingRadius: 12,
                                    bottomLeadingRadius: 0,
                                    bottomTrailingRadius: 0,
                                    topTrailingRadius: 12
                                )
                            )
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.system(size: 30))
                                    .foregroundColor(.gray)
                            )
                    case .empty:
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: width, height: imageHeight)
                            .clipShape(
                                .rect(
                                    topLeadingRadius: 12,
                                    bottomLeadingRadius: 0,
                                    bottomTrailingRadius: 0,
                                    topTrailingRadius: 12
                                )
                            )
                            .overlay(
                                ProgressView()
                            )
                    @unknown default:
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: width, height: imageHeight)
                            .clipShape(
                                .rect(
                                    topLeadingRadius: 12,
                                    bottomLeadingRadius: 0,
                                    bottomTrailingRadius: 0,
                                    topTrailingRadius: 12
                                )
                            )
                    }
                }
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: width, height: imageHeight)
                    .clipShape(
                        .rect(
                            topLeadingRadius: 12,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 12
                        )
                    )
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 30))
                            .foregroundColor(.gray)
                    )
            }
            
            // Location Name
            if !formattedLocation.isEmpty {
                Text(formattedLocation)
                    .font(FontManager.primaryText())
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .frame(width: width, height: 15)
                    .background(
                        Constants.Colors.primary
                            .clipShape(
                                .rect(
                                    topLeadingRadius: 0,
                                    bottomLeadingRadius: 12,
                                    bottomTrailingRadius: 12,
                                    topTrailingRadius: 0
                                )
                            )
                    )
            }
        }
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

// MARK: - Previews
struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView()
    }
} 
