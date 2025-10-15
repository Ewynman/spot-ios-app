//
//  ReportSheet.swift
//  Spot
//
//  Created by Wynman, Edward on 8/14/25.
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

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
            SpotLogger.error("Report submission missing required data")
            return
        }

        isSubmitting = true

        do {
            // Submit report to Firestore
            let reportData: [String: Any] = [
                "spotId": spotId,
                "reporterId": reporterId,
                "ownerId": ownerId,
                "reason": reason.rawValue,
                "details": details.trimmingCharacters(in: .whitespacesAndNewlines),
                "createdAt": FieldValue.serverTimestamp(),
                "platform": "iOS",
                "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
            ]

            try await Firestore.firestore().collection("reports").addDocument(data: reportData)

            // Block user if requested
            if shouldBlockUser {
                try await authVM.blockUser(userId: ownerId)
                SpotLogger.info("User blocked during report: \(ownerId)")
            }

            SpotLogger.info("Report submitted: spotId=\(spotId), reason=\(reason.rawValue), blocked=\(shouldBlockUser)")
            showSuccessMessage = true

        } catch {
            SpotLogger.error("Failed to submit report: \(error.localizedDescription)")
            isSubmitting = false
        }
    }
}
