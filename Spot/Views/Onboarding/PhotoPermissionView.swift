import SwiftUI
import Photos

struct PhotoPermissionView: View {
    let authDestination: NotificationPermissionView.AuthDestination
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var permissionManager: PermissionManager
    @State private var navigateToCamera = false

    var body: some View {
        ZStack {
            Constants.Colors.background.ignoresSafeArea()
            VStack(spacing: 22) {
                HStack {
                    CustomBackButton { dismiss() }
                    Spacer()
                }
                .padding(.top, 8)
                .padding(.horizontal)

                VStack(spacing: 8) {
                    Text("Allow").font(FontManager.sectionHeader()).foregroundColor(Constants.Colors.primary)
                    Text("Photo Access").font(FontManager.sectionHeader()).foregroundColor(Constants.Colors.primary)
                }

                Text("Spot needs your photo library so you can upload spots from gallery.")
                    .font(FontManager.primaryText())
                    .multilineTextAlignment(.center)
                    .foregroundColor(Constants.Colors.primary)

                Spacer()
                Image("waves").resizable().aspectRatio(contentMode: .fill).frame(maxWidth: .infinity).frame(height: 200)
                Spacer()

                VStack(spacing: 12) {
                    Button(permissionManager.photoStatus == .notDetermined ? "Allow Photos" : "Open Settings") {
                        if permissionManager.photoStatus == .notDetermined {
                            permissionManager.requestPhotoPermission()
                        } else {
                            permissionManager.openPhotoSettings()
                        }
                    }
                    .font(FontManager.buttonText())
                    .foregroundColor(Constants.Colors.buttonText)
                    .frame(maxWidth: .infinity).padding()
                    .background(Constants.Colors.primary).cornerRadius(20)
                    .buttonStyle(PlainButtonStyle())
                    Button("Maybe Later") { navigateToCamera = true }
                        .font(FontManager.buttonText())
                        .foregroundColor(Constants.Colors.primary)
                        .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 32)
                Spacer()
            }
            .padding(.top)
        }
        .navigationDestination(isPresented: $navigateToCamera) {
            CameraPermissionView(authDestination: authDestination)
        }
        .onAppear {
            permissionManager.updatePermissionStatuses()
            if permissionManager.photoStatus == .authorized || permissionManager.photoStatus == .limited {
                navigateToCamera = true
            }
        }
        .onChange(of: permissionManager.photoStatus) { _, newStatus in
            if newStatus == .authorized || newStatus == .limited {
                navigateToCamera = true
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}
