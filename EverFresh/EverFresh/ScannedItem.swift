import Foundation

/// The draft Item created by POST /api/items/scan.
///
/// Strapi v5 REST responses carry both a numeric `id` and a string `documentId` — only
/// `documentId` is valid for update/delete calls (`PUT /api/items/{documentId}`), so that's
/// what backs Identifiable here.
struct ScannedItem: Identifiable, Codable {
    var documentId: String
    var numericId: Int
    var name: String
    var description: String
    var category: String
    var expiryDate: String
    var photoUrl: String?
    var source: String
    var status: String
    var quantity: Double
    var pricePaid: Double?
    var createdAt: String

    var id: String { documentId }

    enum CodingKeys: String, CodingKey {
        case documentId
        case numericId = "id"
        case name, description, category, expiryDate, photoUrl, source, status, quantity, pricePaid, createdAt
    }

    init(
        documentId: String,
        numericId: Int,
        name: String,
        description: String,
        category: String,
        expiryDate: String,
        photoUrl: String?,
        source: String,
        status: String,
        quantity: Double,
        pricePaid: Double?,
        createdAt: String
    ) {
        self.documentId = documentId
        self.numericId = numericId
        self.name = name
        self.description = description
        self.category = category
        self.expiryDate = expiryDate
        self.photoUrl = photoUrl
        self.source = source
        self.status = status
        self.quantity = quantity
        self.pricePaid = pricePaid
        self.createdAt = createdAt
    }
}

/// POST /api/items/scan wraps the created item as { "item": {...} }.
struct ScanResponse: Codable {
    let item: ScannedItem
}

/// Strapi's collection endpoints wrap results as { "data": [...], "meta": {...} }.
struct StrapiListResponse<T: Decodable>: Decodable {
    let data: [T]
}
