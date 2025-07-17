import Foundation
import FirebaseStorage
import FirebaseAuth
import UIKit

final class ProfilePictureUploader {
    static let shared = ProfilePictureUploader()
    private init() {}

    // For signup flow - user doesn't exist yet, so we need to pass UID
    func uploadProfilePictureForSignup(image: UIImage, uid: String, completion: @escaping (Result<String, Error>) -> Void) {
        // Compress the image to JPEG
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            completion(.failure(NSError(domain: "ProfilePictureUploader", code: 400, userInfo: [NSLocalizedDescriptionKey: "Image conversion failed."])) )
            return
        }

        let filename = "profile_\(uid).jpg"
        let storageRef = Storage.storage().reference().child("profile_pictures/\(filename)")

        storageRef.putData(imageData, metadata: nil) { _, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            storageRef.downloadURL { url, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let imageUrl = url?.absoluteString else {
                    completion(.failure(NSError(domain: "ProfilePictureUploader", code: 500, userInfo: [NSLocalizedDescriptionKey: "URL not found."])) )
                    return
                }

                completion(.success(imageUrl))
            }
        }
    }

    // For existing users updating their profile picture
    func uploadProfilePicture(image: UIImage, completion: @escaping (Result<String, Error>) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(.failure(NSError(domain: "ProfilePictureUploader", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not logged in"])))
            return
        }

        uploadProfilePictureForSignup(image: image, uid: uid, completion: completion)
    }
} 