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
            // Top Navigation
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
            } else if viewModel.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
            } else if let error = viewModel.error {
                Text(error.localizedDescription)
                    .foregroundColor(.red)
                    .padding()
            }
        }
        .background(Color(hex: "F5F3EF"))
        .onAppear {
            viewModel.loadUserProfile()
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
    
    var body: some View {
        GeometryReader { geometry in
            let sidePadding: CGFloat = 3 // 3px on each side
            let spacing: CGFloat = 5 // 5px between items
            let availableWidth = geometry.size.width - (2 * sidePadding) - spacing // Total width minus padding and middle spacing
            let itemWidth = availableWidth / 2 // Split remaining space into 2 equal columns
            
            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: spacing),
                        GridItem(.flexible(), spacing: spacing)
                    ],
                    spacing: spacing
                ) {
                    ForEach(spots) { spot in
                        SpotGridItem(spot: spot, width: itemWidth)
                    }
                }
                .padding(.horizontal, sidePadding)
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
        // Maintain the same aspect ratio as before (117/175 ≈ 0.67)
        return width * 0.67
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
                            .aspectRatio(contentMode: .fill)
                            .frame(width: width, height: imageHeight)
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
