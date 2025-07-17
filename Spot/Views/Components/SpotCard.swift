import SwiftUI

struct SpotCard: View {
    let spot: Spot
    @State private var isLiked: Bool
    @State private var isSaved: Bool
    
    init(spot: Spot) {
        self.spot = spot
        self._isLiked = State(initialValue: spot.isLiked)
        self._isSaved = State(initialValue: spot.isSaved)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing:12) {
            // User Info Header
            HStack {
                if let profileImageURL = spot.userProfileImageURL {
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
                Text(spot.username)
                    .font(FontManager.primaryText())
                    .fontWeight(.semibold)
                    .foregroundColor(Constants.Colors.primary)
                
                Spacer()
                
                // Location
                if let locationName = spot.locationName {
                    Text(locationName)
                        .font(FontManager.primaryText())
                        .foregroundColor(Constants.Colors.primary)
                }
            }
            .padding(.horizontal,16)
            // Spot Image
            AsyncImage(url: URL(string: spot.imageURL)) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 300)
                    .clipped()
                    .cornerRadius(12)
            } placeholder: {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Constants.Colors.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: 300)
                    .overlay(
                        ProgressView()
                            .foregroundColor(Constants.Colors.primary)
                    )
            }
            .padding(.horizontal,16)
            // Interaction Bar
            HStack {
                // Like Button
                Button(action: {
                    isLiked.toggle()
                    // TODO: Update like count in Firebase
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .foregroundColor(isLiked ? .red : Constants.Colors.primary)
                        Text("\(spot.likes)")
                            .font(FontManager.primaryText())
                            .foregroundColor(Constants.Colors.primary)
                    }
                }
                
                // Save Button
                Button(action: {
                    isSaved.toggle()
                    // TODO: Update save status in Firebase
                }) {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .foregroundColor(isSaved ? Constants.Colors.primary : Constants.Colors.primary)
                }
                
                Spacer()
                
                // Vibe Tag
                Text(spot.vibeTag)
                    .font(FontManager.primaryText())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Constants.Colors.accent)
                    .foregroundColor(Constants.Colors.primary)
                    .cornerRadius(16)
            }
            .padding(.horizontal,16)
            // Caption (if exists)
            if let caption = spot.caption, !caption.isEmpty {
                Text(caption)
                    .font(FontManager.primaryText())
                    .foregroundColor(Constants.Colors.primary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
} 