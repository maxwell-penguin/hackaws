import Foundation
import UIKit

enum ItemServiceError: LocalizedError {
    case invalidImage
    case invalidResponse
    case server(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Couldn't read the selected photo."
        case .invalidResponse:
            return "The server returned an unexpected response."
        case .server(let status, let message):
            return "Server error (\(status)): \(message)"
        }
    }
}

private struct MultipartFormData {
    let boundary = UUID().uuidString
    private var data = Data()

    mutating func addFile(fieldName: String, fileName: String, mimeType: String, fileData: Data) {
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        data.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        data.append(fileData)
        data.append("\r\n".data(using: .utf8)!)
    }

    func finalize() -> Data {
        var result = data
        result.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return result
    }
}

enum ItemService {
    static func scanItem(image: UIImage) async throws -> ScannedItem {
        guard let jpegData = image.jpegData(compressionQuality: 0.8) else {
            throw ItemServiceError.invalidImage
        }

        var form = MultipartFormData()
        form.addFile(fieldName: "image", fileName: "item.jpg", mimeType: "image/jpeg", fileData: jpegData)

        var request = URLRequest(url: URL(string: "\(Config.baseURL)/api/items/scan")!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(form.boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = form.finalize()

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkOK(data: data, response: response)
        return try JSONDecoder().decode(ScanResponse.self, from: data).item
    }

    static func scanReceipt(image: UIImage) async throws -> [ScannedItem] {
        guard let jpegData = image.jpegData(compressionQuality: 0.8) else {
            throw ItemServiceError.invalidImage
        }

        var form = MultipartFormData()
        form.addFile(fieldName: "image", fileName: "receipt.jpg", mimeType: "image/jpeg", fileData: jpegData)

        var request = URLRequest(url: URL(string: "\(Config.baseURL)/api/receipts")!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(form.boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = form.finalize()

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkOK(data: data, response: response)
        return try JSONDecoder().decode(ReceiptScanResponse.self, from: data).items
    }

    /// Returns the item as persisted by the server.
    static func saveItem(_ item: ScannedItem) async throws -> ScannedItem {
        var request = URLRequest(url: URL(string: "\(Config.strapiBaseURL)/api/items/\(item.documentId)")!)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "data": [
                "name": item.name,
                "description": item.description as Any,
                "category": item.category as Any,
                "expiryDate": item.expiryDate as Any,
                "pricePaid": item.pricePaid as Any,
                "quantity": item.quantity as Any,
            ]
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkOK(data: data, response: response)
        await MainActor.run { ReminderScheduler.shared.requestRefresh() }
        return try JSONDecoder().decode(StrapiItemResponse.self, from: data).data
    }

    static func updateQuantity(documentId: String, quantity: Double) async throws {
        var request = URLRequest(url: URL(string: "\(Config.strapiBaseURL)/api/items/\(documentId)")!)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["data": ["quantity": quantity]])

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkOK(data: data, response: response)
        await MainActor.run { ReminderScheduler.shared.requestRefresh() }
    }

    static func updatePosition(documentId: String, x: Double, y: Double) async throws {
        var request = URLRequest(url: URL(string: "\(Config.strapiBaseURL)/api/items/\(documentId)")!)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["data": ["positionX": x, "positionY": y]])

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkOK(data: data, response: response)
    }

    static func markConsumed(documentId: String) async throws {
        var request = URLRequest(url: URL(string: "\(Config.strapiBaseURL)/api/items/\(documentId)")!)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["data": ["status": "consumed"]])

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkOK(data: data, response: response)
        await MainActor.run { ReminderScheduler.shared.requestRefresh() }
    }

    static func deleteItem(documentId: String) async throws {
        var request = URLRequest(url: URL(string: "\(Config.strapiBaseURL)/api/items/\(documentId)")!)
        request.httpMethod = "DELETE"

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkOK(data: data, response: response)
        await MainActor.run { ReminderScheduler.shared.requestRefresh() }
    }

    static func fetchExpiringSoon(withinDays days: Int) async throws -> [ScannedItem] {
        let cutoff = StrapiDate.string(from: Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date())

        var components = URLComponents(string: "\(Config.strapiBaseURL)/api/items")!
        components.queryItems = [
            URLQueryItem(name: "filters[expiryDate][$lte]", value: cutoff),
            URLQueryItem(name: "filters[status][$eq]", value: "active"),
            URLQueryItem(name: "sort", value: "expiryDate:asc"),
        ]

        let (data, response) = try await URLSession.shared.data(from: components.url!)
        try Self.checkOK(data: data, response: response)
        return try JSONDecoder().decode(StrapiListResponse<ScannedItem>.self, from: data).data
    }

    /// Fetches every page (100 per page). Stops on meta.pagination.pageCount, not on how many
    /// records decoded, since the lenient decoder can drop malformed ones. Capped at 10 pages.
    private static func fetchAllPages(_ queryItems: [URLQueryItem]) async throws -> [ScannedItem] {
        var all: [ScannedItem] = []
        for page in 1...10 {
            var components = URLComponents(string: "\(Config.strapiBaseURL)/api/items")!
            components.queryItems = queryItems + [
                URLQueryItem(name: "pagination[pageSize]", value: "100"),
                URLQueryItem(name: "pagination[page]", value: String(page)),
            ]
            let (data, response) = try await URLSession.shared.data(from: components.url!)
            try Self.checkOK(data: data, response: response)
            let decoded = try JSONDecoder().decode(StrapiListResponse<ScannedItem>.self, from: data)
            all += decoded.data
            if page >= (decoded.pageCount ?? 1) { break }
        }
        return all
    }

    static func fetchAllItems() async throws -> [ScannedItem] {
        try await fetchAllPages([URLQueryItem(name: "sort", value: "createdAt:desc")])
    }

    static func fetchActiveItems() async throws -> [ScannedItem] {
        try await fetchAllPages([URLQueryItem(name: "filters[status][$eq]", value: "active")])
    }

    static func fetchRecipeSuggestions(
        category: RecipeCategory,
        inventory: [RecipeInventoryItem],
        count: Int,
        exclude: [String]
    ) async throws -> [RecipeSuggestion] {
        struct Body: Encodable {
            let category: String
            let inventory: [RecipeInventoryItem]
            let count: Int
            let exclude: [String]
        }

        var request = URLRequest(url: URL(string: "\(Config.baseURL)/api/recipe-suggestions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 90  // generation can take a while
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            Body(category: category.rawValue, inventory: inventory, count: count, exclude: exclude)
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkOK(data: data, response: response)
        return try JSONDecoder().decode(RecipeSuggestionsResponse.self, from: data).recipes
    }

    static func fetchRecipeSteps(
        name: String,
        servings: Int?,
        category: RecipeCategory,
        ingredients: [RecipeIngredient]
    ) async throws -> (steps: [String], tip: String?) {
        struct StepIngredient: Encodable {
            let name: String
            let amount: String?
            let required: Bool
        }
        struct Body: Encodable {
            let name: String
            let servings: Int?
            let category: String
            let ingredients: [StepIngredient]
        }
        struct Response: Decodable {
            let steps: [String]
            let tip: String?
        }

        var request = URLRequest(url: URL(string: "\(Config.baseURL)/api/recipe-steps")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Body(
            name: name,
            servings: servings,
            category: category.rawValue,
            ingredients: ingredients.map { StepIngredient(name: $0.name, amount: $0.amount, required: $0.required) }
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkOK(data: data, response: response)
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.steps, decoded.tip)
    }

    private static func checkOK(data: Data, response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ItemServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ItemServiceError.server(status: httpResponse.statusCode, message: message)
        }
    }
}
