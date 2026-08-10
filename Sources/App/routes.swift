import Vapor
import Fluent

func routes(_ app: Application) throws {
    app.get { req async -> String in
        "The Daily News Bot is running."
    }

    app.get("health") { req async throws -> HTTPStatus in
        // Cheap liveness check: make sure the DB is reachable.
        _ = try await User.query(on: req.db).count()
        return .ok
    }
}
