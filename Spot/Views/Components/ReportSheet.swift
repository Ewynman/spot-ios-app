//
//  ReportSheet.swift
//  Spot
//
//  Created by Wynman, Edward on 8/14/25.
//

import SwiftUI
import Supabase

enum ReportReason: String, CaseIterable {
    case inappropriate = "inappropriate"
    case harassment = "harassment"
    case violence = "violence"
    case spam = "spam"
    case misinformation = "misinformation"
    case privacy = "privacy"
    case other = "other"

    var title: String {
        switch self {
        case .inappropriate:
            return "Inappropriate / Nudity or Sexual Content"
        case .harassment:
            return "Harassment or Hate"
        case .violence:
            return "Violence / Dangerous Acts / Drugs"
        case .spam:
            return "Spam or Scams"
        case .misinformation:
            return "Misinformation / Illegal Activity"
        case .privacy:
            return "Privacy / Personal Data"
        case .other:
            return "Other"
        }
    }
}

#Preview {
    let sample = Spot(
        id: "s1",
        userId: "author1",
        username: "author",
        imageURL: "https://picsum.photos/seed/report/800/600",
        vibeTag: "Scenic",
        latitude: 47.6062,
        longitude: -122.3321,
        locationName: "Seattle",
        createdAt: Date()
    )
    let auth = AuthViewModel()
    auth.userId = "viewer1"
    return ReportSheet(spot: sample)
        .environmentObject(auth)
}

struct ReportSheet: View {
    let spot: Spot
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authVM: AuthViewModel
    @State private var selectedReason: ReportReason?
    @State private var details: String = ""
    @State private var shouldBlockUser: Bool = false
    @State private var isSubmitting: Bool = false
    @State private var showSuccessMessage: Bool = false

    private let reasons: [ReportReason] = [
        .inappropriate,
        .harassment,
        .violence,
        .spam,
        .misinformation,
        .privacy,
        .other
    ]

    private var canSubmit: Bool {
        guard let reason = selectedReason else { return false }
        if reason == .other && details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        return !isSubmitting
    }

    private var isOwnSpot: Bool {
        guard let currentUserId = authVM.userId, let ownerId = spot.userId else { return false }
        return currentUserId == ownerId
    }

    var body: some View {
        NavigationView {
            Form {
                if isOwnSpot {
                    Section {
                        Text("You cannot report your own spot.")
                            .foregroundColor(.orange)
                    }
                } else {
                    reasonSection
                    detailsSection
                    blockSection
                }
            }
            .navigationTitle("Report Spot")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSubmitting)
                }

                if !isOwnSpot {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Submit") {
                            Task { await submitReport() }
                        }
                        .disabled(!canSubmit)
                    }
                }
            }
        }
        .alert("Report Submitted", isPresented: $showSuccessMessage) {
            Button("OK") { dismiss() }
        } message: {
            Text("Thanks for helping keep our community safe.")
        }
        .onChange(of: details) { _, newValue in
            if newValue.count > 500 {
                details = String(newValue.prefix(500))
            }
        }
    }

    // MARK: - Computed Views
    private var reasonSection: some View {
        Section(header: Text("Reason for reporting")) {
            ForEach(reasons, id: \.self) { reason in
                reasonRow(for: reason)
            }
        }
    }

    private func reasonRow(for reason: ReportReason) -> some View {
        Button {
            selectedReason = reason
        } label: {
            HStack {
                Text(reason.title)
                    .foregroundColor(Constants.Colors.textPrimary)
                Spacer()
                if selectedReason == reason {
                    Image(systemName: "checkmark")
                        .foregroundColor(Constants.Colors.primary)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var detailsSection: some View {
        Section {
            TextEditor(text: $details)
                .frame(minHeight: 80)
                .disabled(isSubmitting)
        } header: {
            Text("Additional details (optional)")
        } footer: {
            Text("\(details.count)/500 characters")
        }
    }

    private var blockSection: some View {
        Section {
            Toggle("Also block this user", isOn: $shouldBlockUser)
                .disabled(isSubmitting)
        }
    }

    @MainActor
    private func submitReport() async {
        guard let reason = selectedReason,
              let reporterId = authVM.userId,
              let ownerId = spot.userId,
              let spotId = spot.id else {
            SpotLogger.log(ReportSheetLogs.submissionMissingRequiredData)
            return
        }

        isSubmitting = true

        do {
            guard let reporterUUID = UUID(uuidString: reporterId),
                  let ownerUUID = UUID(uuidString: ownerId),
                  let spotUUID = UUID(uuidString: spotId) else {
                throw NSError(domain: "ReportSheet", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid report IDs"])
            }
            struct ReportInsert: Encodable {
                let spot_id: UUID
                let reporter_id: UUID
                let owner_id: UUID
                let reason: String
                let details: String
                let platform: String
                let app_version: String
            }
            try await supabase
                .from("reports")
                .insert(ReportInsert(
                    spot_id: spotUUID,
                    reporter_id: reporterUUID,
                    owner_id: ownerUUID,
                    reason: reason.rawValue,
                    details: details.trimmingCharacters(in: .whitespacesAndNewlines),
                    platform: "iOS",
                    app_version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
                ))
                .execute()

            // Block user if requested
            if shouldBlockUser {
                try await authVM.blockUser(userId: ownerId)
                SpotLogger.log(ReportSheetLogs.userBlockedDuringReport, details: ["ownerId": ownerId])
            }

            SpotLogger.log(ReportSheetLogs.reportSubmitted, details: ["spotId": spotId, "reason": reason.rawValue, "blocked": shouldBlockUser])
            showSuccessMessage = true

        } catch {
            SpotLogger.log(ReportSheetLogs.submitFailed, details: ["error": error.localizedDescription])
            isSubmitting = false
        }
    }
}
