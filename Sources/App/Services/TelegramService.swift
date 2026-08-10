import Vapor

/// Minimal wrapper around the subset of the Telegram Bot API we need:
/// sendMessage + getUpdates (long polling). No webhook server required,
/// which makes this trivial to run locally.
struct TelegramService {
    let client: Client
    let token: String
    let logger: Logger

    private var baseURL: String {
        "https://api.telegram.org/bot\(token)"
    }

    /// Sends a text message to a chat. Telegram's hard limit is 4096 chars;
    /// we trim defensively so a long article summary never causes a failed send.
    func sendMessage(chatID: Int64, text: String) async {
        let trimmed = text.count > 4000 ? String(text.prefix(4000)) + "…" : text
        let uri = URI(string: "\(baseURL)/sendMessage")
        do {
            let response = try await client.post(uri) { req in
                try req.content.encode([
                    "chat_id": "\(chatID)",
                    "text": trimmed,
                    "parse_mode": "HTML",
                    "disable_web_page_preview": "false"
                ], as: .urlEncodedForm)
            }
            if response.status != .ok {
                logger.warning("Telegram sendMessage failed with status \(response.status) for chat \(chatID)")
            }
        } catch {
            logger.error("Telegram sendMessage error for chat \(chatID): \(error)")
        }
    }

    /// Sends a photo with a caption underneath — Telegram accepts a plain image
    /// URL for the `photo` field, so no file upload/multipart is needed; Telegram
    /// fetches the image itself. Returns true on success so callers can fall back
    /// to a text-only message if the image URL turns out to be broken or blocked.
    /// Caption limit is 1024 chars (stricter than the 4096 limit for sendMessage).
    func sendPhoto(chatID: Int64, photoURL: String, caption: String) async -> Bool {
        let trimmed = caption.count > 1024 ? String(caption.prefix(1024)) + "…" : caption
        let uri = URI(string: "\(baseURL)/sendPhoto")
        do {
            let response = try await client.post(uri) { req in
                try req.content.encode([
                    "chat_id": "\(chatID)",
                    "photo": photoURL,
                    "caption": trimmed,
                    "parse_mode": "HTML"
                ], as: .urlEncodedForm)
            }
            if response.status != .ok {
                logger.warning("Telegram sendPhoto failed with status \(response.status) for chat \(chatID); will fall back to text.")
                return false
            }
            return true
        } catch {
            logger.error("Telegram sendPhoto error for chat \(chatID): \(error)")
            return false
        }
    }

    /// Long-polls Telegram for new updates (messages sent to the bot), starting
    /// after `offset`. Waits up to `timeout` seconds server-side for a message
    /// to arrive (Telegram's long-polling mechanism), so this call is cheap to
    /// loop on continuously.
    func getUpdates(offset: Int64?, timeout: Int = 25) async throws -> [TelegramUpdate] {
        var uriString = "\(baseURL)/getUpdates?timeout=\(timeout)"
        if let offset {
            uriString += "&offset=\(offset)"
        }
        let uri = URI(string: uriString)
        let response = try await client.get(uri)
        let decoded = try response.content.decode(TelegramGetUpdatesResponse.self)
        return decoded.result
    }
}

// MARK: - Telegram API response types

struct TelegramGetUpdatesResponse: Content {
    let ok: Bool
    let result: [TelegramUpdate]
}

struct TelegramUpdate: Content {
    let updateID: Int64
    let message: TelegramMessage?

    enum CodingKeys: String, CodingKey {
        case updateID = "update_id"
        case message
    }
}

struct TelegramMessage: Content {
    let messageID: Int64
    let chat: TelegramChat
    let text: String?
    let from: TelegramUser?

    enum CodingKeys: String, CodingKey {
        case messageID = "message_id"
        case chat, text, from
    }
}

struct TelegramChat: Content {
    let id: Int64
    let type: String
}

struct TelegramUser: Content {
    let id: Int64
    let username: String?
    let firstName: String?

    enum CodingKeys: String, CodingKey {
        case id, username
        case firstName = "first_name"
    }
}
