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

    static func saveItem(_ item: ScannedItem) async throws {
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
    }

    static func updateQuantity(documentId: String, quantity: Double) async throws {
        var request = URLRequest(url: URL(string: "\(Config.strapiBaseURL)/api/items/\(documentId)")!)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["data": ["quantity": quantity]])

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkOK(data: data, response: response)
    }

    static func updatePosition(documentId: String, x: Double, y: Double) async throws {
        var request = URLRequest(url: URL(string: "\(Config.strapiBaseURL)/api/items/\(documentId)")!)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["data": ["positionX": x, "positionY": y]])

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkOK(data: data, response: response)
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

    static func fetchAllItems() async throws -> [ScannedItem] {
        var components = URLComponents(string: "\(Config.strapiBaseURL)/api/items")!
        components.queryItems = [
            URLQueryItem(name: "sort", value: "createdAt:desc"),
        ]

        let (data, response) = try await URLSession.shared.data(from: components.url!)
        try Self.checkOK(data: data, response: response)
        return try JSONDecoder().decode(StrapiListResponse<ScannedItem>.self, from: data).data
    }

    static func fetchActiveItems() async throws -> [ScannedItem] {
        var components = URLComponents(string: "\(Config.strapiBaseURL)/api/items")!
        components.queryItems = [
            URLQueryItem(name: "filters[status][$eq]", value: "active"),
        ]

        let (data, response) = try await URLSession.shared.data(from: components.url!)
        try Self.checkOK(data: data, response: response)
        return try JSONDecoder().decode(StrapiListResponse<ScannedItem>.self, from: data).data
    }

    static func fetchRecipeSuggestions(expiringItems: [String], activeInventory: [String]) async throws -> [RecipeSuggestion] {
        var request = URLRequest(url: URL(string: "\(Config.baseURL)/api/recipe-suggestions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "expiringItems": expiringItems,
            "activeInventory": activeInventory,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkOK(data: data, response: response)
        return try JSONDecoder().decode(RecipeSuggestionsResponse.self, from: data).recipes
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
