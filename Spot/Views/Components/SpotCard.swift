import SwiftUI

struct SpotCard: View {
    let spot: Spot
    @State private var isLiked: Bool
    @State private var isSaved: Bool
    
    init(spot: Spot) {
        self.spot = spot
        self._isLiked = State(initialValue: spot.isLiked ?? false)
        self._isSaved = State(initialValue: spot.isSaved ?? false)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing:12) {
            // User Info Header
            HStack {
                if let userId = spot.userId {
                    NavigationLink {
                        UserProfileView(userId: userId)
                            .navigationBarBackButtonHidden(true)
                    } label: {
                        HStack {
                            // Profile Image
                            if let profileImageURL = spot.userProfileImageURL, !profileImageURL.isEmpty {
                                AsyncImage(url: URL(string: profileImageURL)) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 32, height: 32)
                                        .clipShape(Circle())
                                } placeholder: {
                                    Circle()
                                        .fill(Constants.Colors.background)
                                        .frame(width: 32, height: 32)
                                        .overlay(
                                            Image(systemName: "person.fill")
                                                .font(.system(size: 16))
                                                .foregroundColor(Constants.Colors.primary)
                                        )
                                }
                            } else {
                                Circle()
                                    .fill(Constants.Colors.background)
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(Constants.Colors.primary)
                                    )
                            }
                            
                            // Username
                            Text(spot.username ?? "")
                                .font(FontManager.primaryText())
                                .fontWeight(.semibold)
                                .foregroundColor(Constants.Colors.primary)
                        }
                    }
                }
                
                Spacer()
                
                // Location
                if let locationName = spot.locationName, !locationName.isEmpty {
                    Text(locationName)
                        .font(FontManager.primaryText())
                        .foregroundColor(Constants.Colors.primary)
                }
            }
            .padding(.horizontal,10)
            
            // Spot Image
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Constants.Colors.background)
                GeometryReader { geo in
                    if let imageURL = spot.imageURL, !imageURL.isEmpty {
                        AsyncImage(url: URL(string: imageURL)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geo.size.width, height: 220)
                                .clipped()
                                .cornerRadius(12)
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Constants.Colors.background)
                                .frame(width: geo.size.width, height: 220)
                                .overlay(
                                    ProgressView()
                                        .foregroundColor(Constants.Colors.primary)
                                )
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Constants.Colors.background)
                            .frame(width: geo.size.width, height: 220)
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.system(size: 40))
                                    .foregroundColor(Constants.Colors.primary)
                            )
                    }
                }
                .frame(height: 220)
            }
            .frame(height: 220)
            .padding(.horizontal, 5)
            
            // Interaction Bar
            HStack {
                // Like Button
                Button(action: { isLiked.toggle() }) {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .foregroundColor(isLiked ? .red : .gray)
                }
                // Save Button
                Button(action: { isSaved.toggle() }) {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .foregroundColor(isSaved ? Constants.Colors.primary : .gray)
                }
                Spacer()
                // Vibe Tag
                if let vibe = spot.vibeTag, !vibe.isEmpty {
                    Text(vibe)
                        .font(FontManager.primaryText())
                        .foregroundColor(Constants.Colors.primary)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 12)
                        .background(Constants.Colors.accent)
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal,10)
            .padding(.bottom, 8)
        }
        .background(Constants.Colors.background)
        .padding(.horizontal, 0)
        .padding(.vertical, 4)
    }
}

#Preview {
    SpotCard(spot: Spot(
        id: "test123",
        userId: "user123",
        username: "TestUser",
        userProfileImageURL: nil,
        imageURL: "https://via.placeholder.com/300",
        caption: "A cool spot!",
        vibeTag: "Chill Spot",
        latitude: 37.78,
        longitude: -122.4,
        locationName: "Test Location",
        likes: 5,
        isLiked: false,
        isSaved: false,
    ))
}
