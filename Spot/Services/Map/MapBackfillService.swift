import Foundation
import FirebaseFirestore

enum MapBackfillService {
    static func backfillMissingGeohashes(limit: Int = 1000) async {
        let db = Firestore.firestore()
        do {
            let snap = try await db.collection("spots").limit(to: limit).getDocuments()
            for doc in snap.documents {
                let data = doc.data()
                if data["geohash"] as? String == nil,
                   let lat = data["latitude"] as? Double,
                   let lon = data["longitude"] as? Double {
                    let gh = GeoHash.encode(latitude: lat, longitude: lon, precision: 7)
                    try await db.collection("spots").document(doc.documentID).updateData(["geohash": gh])
                }
            }
            SpotLogger.log(MapBackfillServiceLogs.backfillGeohashComplete)
        } catch {
            SpotLogger.log(MapBackfillServiceLogs.backfillGeohashFailed, details: ["error": error.localizedDescription])
        }
    }
}
