//
//  SparkLibraryService.swift
//  ReportsApp
//
//  Calls behind Spark's recipes, schedules and runs. The server trusts the
//  Bearer token here and never the typeable chat_user_id, so every request
//  goes through withAppIdentity(); without a token these read as logged out.
//

import Foundation

enum SparkLibraryService {
    struct ServiceError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private static let base = ChatManager.serverBaseURL

    // MARK: - Lists

    struct RecipeList: Decodable {
        let loggedIn: Bool
        let recipes: [SparkRecipe]
        let starters: [SparkRecipe]
        enum CodingKeys: String, CodingKey {
            case loggedIn = "logged_in"
            case recipes, starters
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            loggedIn = (try? c.decode(Bool.self, forKey: .loggedIn)) ?? false
            recipes = (try? c.decode([SparkRecipe].self, forKey: .recipes)) ?? []
            starters = (try? c.decode([SparkRecipe].self, forKey: .starters)) ?? []
        }
    }

    static func recipes() async throws -> RecipeList {
        try await get("/recipes/", as: RecipeList.self)
    }

    static func schedules() async throws -> [SparkSchedule] {
        struct Wrapper: Decodable { let schedules: [SparkSchedule]? }
        return try await get("/schedules/", as: Wrapper.self).schedules ?? []
    }

    static func runs(limit: Int = 100, scheduleID: String? = nil) async throws -> [SparkRun] {
        struct Wrapper: Decodable { let runs: [SparkRun]? }
        var path = "/runs/?limit=\(limit)"
        if let scheduleID { path += "&schedule_id=\(scheduleID)" }
        return try await get(path, as: Wrapper.self).runs ?? []
    }

    static func segmentCatalog() async throws -> SparkSegmentCatalog {
        try await get("/recipes/segments/", as: SparkSegmentCatalog.self)
    }

    // MARK: - Running a recipe

    struct BuiltPrompt {
        let prompt: String
        let planFirst: Bool?
    }

    /// The recipe's prompt for this place and market focus.
    static func prompt(recipeID: String, geo: String, segmentValues: [String]) async throws -> BuiltPrompt {
        let json = try await post("/recipes/prompt/", ["id": recipeID, "geo": geo, "segment_values": segmentValues])
        guard let prompt = json["prompt"] as? String, !prompt.isEmpty else {
            throw ServiceError(message: (json["error"] as? String) ?? "Couldn't build this recipe.")
        }
        return BuiltPrompt(prompt: prompt, planFirst: json["plan_first"] as? Bool)
    }

    /// Records a run started by hand. The id links the run to the chat.
    static func markUsed(recipeID: String, geo: String) async -> Int? {
        let json = try? await post("/recipes/used/", ["id": recipeID, "geo": geo])
        return (json?["run_id"] as? NSNumber)?.intValue
    }

    // MARK: - Managing recipes

    /// A new recipe from a plain description of what the member wants.
    static func createRecipe(describing description: String, threadID: String? = nil) async throws -> SparkRecipe {
        var body: [String: Any] = ["prompt": description, "source": threadID == nil ? "describe" : "chat"]
        if let threadID { body["thread_id"] = threadID }
        return try await recipe(from: post("/recipes/save/", body))
    }

    /// Copies a starter into the member's own recipes.
    static func fork(starterID: String) async throws -> SparkRecipe {
        try await recipe(from: post("/recipes/fork/", ["id": starterID]))
    }

    static func rename(recipeID: String, to name: String) async throws -> SparkRecipe {
        try await recipe(from: post("/recipes/update/", ["id": recipeID, "name": name]))
    }

    static func deleteRecipe(id: String) async throws {
        _ = try await post("/recipes/delete/", ["id": id])
    }

    // MARK: - Managing schedules

    static func createSchedule(recipeID: String, cadence: String, geo: String,
                               segmentValues: [String], threadID: String?) async throws -> SparkSchedule {
        var body: [String: Any] = [
            "recipe_id": recipeID,
            "cadence": cadence,
            "geo_label": geo,
            "segment_values": segmentValues,
        ]
        if let threadID { body["thread_id"] = threadID }
        return try await schedule(from: post("/schedules/save/", body))
    }

    static func setScheduleActive(id: String, active: Bool) async throws -> SparkSchedule {
        try await schedule(from: post("/schedules/update/", ["id": id, "active": active]))
    }

    static func deleteSchedule(id: String) async throws {
        _ = try await post("/schedules/update/", ["id": id, "delete": true])
    }

    /// Runs the schedule now and emails the result. Slow: the server writes
    /// the whole answer before it replies.
    static func runScheduleNow(id: String) async throws {
        _ = try await post("/schedules/run/", ["id": id], timeout: 300)
    }

    // MARK: - Plumbing

    private static func recipe(from json: [String: Any]) throws -> SparkRecipe {
        guard let object = json["recipe"],
              let data = try? JSONSerialization.data(withJSONObject: object) else {
            throw ServiceError(message: "The Hub didn't send the recipe back.")
        }
        return try JSONDecoder().decode(SparkRecipe.self, from: data)
    }

    private static func schedule(from json: [String: Any]) throws -> SparkSchedule {
        guard let object = json["schedule"],
              let data = try? JSONSerialization.data(withJSONObject: object) else {
            throw ServiceError(message: "The Hub didn't send the schedule back.")
        }
        return try JSONDecoder().decode(SparkSchedule.self, from: data)
    }

    private static func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        guard let url = URL(string: base + path) else { throw ServiceError(message: "Bad address") }
        let (data, response) = try await URLSession.shared.data(for: .app(url))
        try check(response, data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// POSTs JSON and returns the reply object. Throws with the server's
    /// error text on a non-2xx reply or `ok: false`.
    @discardableResult
    private static func post(_ path: String, _ body: [String: Any], timeout: TimeInterval = 60) async throws -> [String: Any] {
        guard let url = URL(string: base + path) else { throw ServiceError(message: "Bad address") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request.withAppIdentity())
        try check(response, data)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if (json["ok"] as? Bool) == false {
            throw ServiceError(message: friendly(json["error"] as? String))
        }
        return json
    }

    private static func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) else { return }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        throw ServiceError(message: friendly(json?["error"] as? String, status: http.statusCode))
    }

    private static func friendly(_ code: String?, status: Int = 0) -> String {
        let text = code ?? ""
        switch text {
        case "not_logged_in": return "Sign out and back in to use recipes on this device."
        case "recipe_not_found": return "That recipe isn't there any more."
        case "not_found": return "That schedule isn't there any more."
        case "": return status > 0 ? "The Hub answered \(status). Try again in a minute." : "Something went wrong. Try again in a minute."
        default: return text
        }
    }
}
