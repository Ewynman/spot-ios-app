//
//  ProfileView.swift
//  Spot
//
//  Created by Edward Wynman on 8/13/25.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct FollowRequestsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var items: [FollowRequest] = []
    @State private var isLoading: Bool = false
    @State private var last: DocumentSnapshot?
    @State private var hasMore: Bool = true
    @State private var processing: Set<String> = []

    private let pageSize: Int = 24
    private let service = FollowRequestsService.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("Back to Profile")
                    }
                    .foregroundColor(Constants.Colors.primary)
                }
                .buttonStyle(PlainButtonStyle())
                Spacer()
                Text("Follow Requests")
                    .font(FontManager.sectionHeader())
                    .foregroundColor(Constants.Colors.primary)
                Spacer().frame(width: 44)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if isLoading && items.isEmpty {
                Spacer()
                ProgressView()
                Spacer()
            } else if items.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "lock.fill").font(.system(size: 48)).foregroundColor(.gray)
                    Text("No pending requests.")
                        .font(FontManager.primaryText())
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(items, id: \.id) { req in
                            row(req)
                                .onAppear { if req.id == items.last?.id { Task { await loadMore() } } }
                        }
                        if isLoading { ProgressView().padding() }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                .refreshable { await refresh() }
            }
        }
        .background(Color(hex: "F5F3EF"))
        .task { await refresh() }
        .navigationBarBackButtonHidden(true)
    }

    @ViewBuilder
    private func row(_ req: FollowRequest) -> some View {
        HStack(spacing: 12) {
            if let urlStr = req.photoURL, let url = URL(string: urlStr) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Image(systemName: "person.circle.fill").resizable().foregroundColor(.gray)
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())
            } else {
                Image(systemName: "person.circle.fill").resizable().foregroundColor(.gray)
                    .frame(width: 44, height: 44)
            }

            VStack(alignment: .leading) {
                Text(req.username ?? req.requesterUid)
                    .font(FontManager.primaryText())
                    .foregroundColor(.black)
                if let created = req.createdAt {
                    Text(created, style: .relative)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            Spacer()

            HStack(spacing: 8) {
                Button {
                    Task { await accept(req) }
                } label: {
                    Text("Accept")
                        .font(FontManager.primaryText())
                        .foregroundColor(Constants.Colors.buttonText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Constants.Colors.primary)
                        .cornerRadius(8)
                }
                .disabled(processing.contains(req.id))
                .buttonStyle(PlainButtonStyle())

                Button {
                    Task { await deny(req) }
                } label: {
                    Text("Deny")
                        .font(FontManager.primaryText())
                        .foregroundColor(Constants.Colors.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Constants.Colors.primary, lineWidth: 1))
                }
                .disabled(processing.contains(req.id))
                .buttonStyle(PlainButtonStyle())
            }
        }
        .opacity(processing.contains(req.id) ? 0.5 : 1.0)
        .padding(12)
        .background(Color.white)
        .cornerRadius(12)
    }

    // MARK: Data
    private func refresh() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        await MainActor.run { isLoading = true; items = []; last = nil; hasMore = true }
        do {
            let page = try await service.fetchPage(for: uid, last: nil, pageSize: pageSize)
            await MainActor.run { items = page.items; last = page.last; hasMore = (page.items.count == pageSize); isLoading = false }
            SpotLogger.info("Follow.Requests.Opened")
        } catch {
            await MainActor.run { isLoading = false }
            SpotLogger.error("FollowRequestsView refresh failed: \(error.localizedDescription)")
        }
    }

    private func loadMore() async {
        guard hasMore, !isLoading, let uid = Auth.auth().currentUser?.uid else { return }
        await MainActor.run { isLoading = true }
        do {
            let page = try await service.fetchPage(for: uid, last: last, pageSize: pageSize)
            await MainActor.run {
                items.append(contentsOf: page.items)
                last = page.last
                hasMore = (page.items.count == pageSize)
                isLoading = false
            }
        } catch {
            await MainActor.run { isLoading = false }
            SpotLogger.error("FollowRequestsView loadMore failed: \(error.localizedDescription)")
        }
    }

    private func accept(_ req: FollowRequest) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        processing.insert(req.id)
        do {
            try await service.accept(requesterUid: req.requesterUid, targetUid: uid)
            await MainActor.run {
                items.removeAll { $0.id == req.id }
                _ = processing.remove(req.id)
            }
        } catch {
            await MainActor.run {
                _ = processing.remove(req.id)
            }
            SpotLogger.error("Accept failed: \(error.localizedDescription)")
        }
    }

    private func deny(_ req: FollowRequest) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        processing.insert(req.id)
        do {
            try await service.deny(requesterUid: req.requesterUid, targetUid: uid)
            await MainActor.run {
                items.removeAll { $0.id == req.id }
                _ = processing.remove(req.id)
            }
        } catch {
            await MainActor.run {
                _ = processing.remove(req.id)
            }
            SpotLogger.error("Deny failed: \(error.localizedDescription)")
        }
    }
}

#Preview {
    FollowRequestsView()
}
