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
        VStack(alignment: .leading, spacing: 12) {
            // MARK: - Header: Profile + Location
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
                    .buttonStyle(PlainButtonStyle())
                }
                
                Spacer()
                
                // Location
                if let locationName = spot.locationName, !locationName.isEmpty {
                    Text(locationName)
                        .font(FontManager.primaryText())
                        .foregroundColor(Constants.Colors.primary)
                }
            }
            .padding(.horizontal, 12)

            // MARK: - Spot Image
            if let imageURL = spot.imageURL, !imageURL.isEmpty {
                AsyncImage(url: URL(string: imageURL)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 400) // Max height like Instagram
                        .clipped()
                        .cornerRadius(12)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Constants.Colors.background)
                        .frame(maxWidth: .infinity, maxHeight: 400)
                        .overlay(
                            ProgressView()
                                .foregroundColor(Constants.Colors.primary)
                        )
                }
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Constants.Colors.background)
                    .frame(maxWidth: .infinity, maxHeight: 400)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 40))
                            .foregroundColor(Constants.Colors.primary)
                    )
            }

            // MARK: - Interaction Bar BELOW the image
            HStack {
                HStack(spacing: 16) {
                    Button(action: { isLiked.toggle() }) {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .foregroundColor(isLiked ? .red : .gray)
                            .font(.system(size: 22))
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button(action: { isSaved.toggle() }) {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                            .foregroundColor(isSaved ? Constants.Colors.primary : .gray)
                            .font(.system(size: 22))
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                Spacer()

                if let vibe = spot.vibeTag, !vibe.isEmpty {
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
            .padding(.bottom, 10)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Constants.Colors.background)
    }
}
