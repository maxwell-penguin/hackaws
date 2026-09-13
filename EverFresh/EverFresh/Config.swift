import Foundation

enum Config {
    /// The Next.js backend that hosts /api/items/scan.
    static let baseURL = "https://hackaws.vercel.app"

    /// The Strapi instance, used for direct REST calls (e.g. PUT /api/items/:id).
    static let strapiBaseURL = "https://hackaws-production.up.railway.app"
}
