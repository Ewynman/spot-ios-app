import SwiftUI

struct SearchView: View {
    @StateObject private var vm = SearchViewModel()
    @State private var path: [String] = []
    @FocusState private var focused: Bool
    
    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").foregroundColor(.gray)
                    TextField("Search users, locations, vibes", text: $vm.query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .foregroundColor(Constants.Colors.textPrimary)
                    if !vm.query.isEmpty {
                        Button(action: { vm.query = ""; vm.clear(); focused = false }) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(Constants.Colors.textPrimary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(12)
                .background(Color.white)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Constants.Colors.primary, lineWidth: 1))
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // Segments styled like homepage tabs (Users / Locations / Vibes)
                HStack(spacing: 32) {
                    ForEach(SearchViewModel.Segment.allCases, id: \.self) { seg in
                        VStack(spacing: 4) {
                            Text(seg.rawValue)
                                .font(FontManager.primaryText())
                                .fontWeight(vm.segment == seg ? .semibold : .regular)
                                .foregroundColor(vm.segment == seg ? Constants.Colors.primary : .gray)
                            Rectangle()
                                .fill(vm.segment == seg ? Constants.Colors.primary : Color.clear)
                                .frame(height: 2)
                        }
                        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { vm.segment = seg } }
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        // Users tab only
                        if vm.segment == .users {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(vm.users.indices, id: \.self) { i in
                                    let u = vm.users[i]
                                    HStack(spacing: 12) {
                                        UserAvatar(urlString: u["profileImageURL"] as? String)
                                        Text((u["username"] as? String) ?? "")
                                            .font(FontManager.primaryText())
                                            .foregroundColor(Constants.Colors.primary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16)
                                }
                            }
                        }

                        // Locations tab
                        if vm.segment == .locations {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(vm.locations, id: \.self) { name in
                                    Button { Task { await vm.openLocation(name) } } label: {
                                        Text(name.capitalized)
                                            .font(FontManager.primaryText())
                                            .foregroundColor(Constants.Colors.primary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .padding(.horizontal, 16)
                                }
                            }
                        }

                        // Vibes tab
                        if vm.segment == .vibes {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(vm.vibes, id: \.self) { tag in
                                    Button { Task { await vm.openVibe(tag) } } label: {
                                        VibeChip(text: tag.capitalized)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .padding(.horizontal, 16)
                                }
                            }
                        }

                        // Grid when a location or vibe chosen
                        if let title = vm.gridTitle {
                            Divider().padding(.horizontal, 16)
                            HStack { Text(title.capitalized).font(FontManager.sectionHeader()); Spacer() }
                                .foregroundColor(Constants.Colors.primary)
                                .padding(.horizontal, 16)
                            SpotsGridView(spots: vm.gridSpots, onSpotTapped: { _ in }, onLoadMore: {
                                Task { await vm.loadMoreGrid(isVibe: title.hasPrefix("#")) }
                            })
                            .frame(maxHeight: .infinity)
                        }
                    }
                }
            }
            .navigationBarBackButtonHidden(true)
            .background(Color(hex: "F5F3EF"))
        }
    }
}

struct UserAvatar: View {
    let urlString: String?
    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Color.gray.opacity(0.2)
                }
            } else {
                Color.gray.opacity(0.2)
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(Circle())
    }
}

struct VibeChip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(FontManager.primaryText())
            .foregroundColor(Constants.Colors.primary)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(Constants.Colors.accent)
            .cornerRadius(12)
    }
}

private struct SectionHeader: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        Text(text)
            .font(FontManager.sectionHeader())
            .foregroundColor(Constants.Colors.primary)
            .padding(.horizontal, 16)
    }
}


