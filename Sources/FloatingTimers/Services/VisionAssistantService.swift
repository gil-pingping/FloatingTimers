import Foundation

protocol VisionAssistantStreaming: Sendable {
    func streamResponse(
        provider: AIProvider,
        model: String,
        apiKey: String,
        prompt: String,
        imageData: Data?,
        mimeType: String?,
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws
}

enum VisionAssistantError: LocalizedError {
    case missingAPIKey(String)
    case missingModel(String)
    case httpError(Int, String)
    case serviceError(String)
    case emptyResponse
    case cancelled

    var errorDescription: String? {
        switch self {
        case let .missingAPIKey(provider):
            return "\(provider) API 키가 비어 있습니다."
        case let .missingModel(provider):
            return "\(provider) 모델명이 비어 있습니다."
        case let .httpError(code, message):
            return "AI 요청 실패 (\(code)): \(message)"
        case let .serviceError(message):
            return message
        case .emptyResponse:
            return "AI 응답이 비어 있습니다."
        case .cancelled:
            return "AI 요청이 취소되었습니다."
        }
    }
}

struct UnavailableVisionAssistantService: VisionAssistantStreaming, Sendable {
    func streamResponse(
        provider _: AIProvider,
        model _: String,
        apiKey _: String,
        prompt _: String,
        imageData _: Data?,
        mimeType _: String?,
        onDelta _: @escaping @Sendable (String) -> Void
    ) async throws {
        throw VisionAssistantError.serviceError("이 환경에서는 AI 서비스가 연결되지 않았습니다.")
    }
}

final class VisionAssistantService: VisionAssistantStreaming, @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config)
    }()) {
        self.session = session
    }

    func streamResponse(
        provider: AIProvider,
        model: String,
        apiKey: String,
        prompt: String,
        imageData: Data?,
        mimeType: String?,
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedModel.isEmpty else {
            throw VisionAssistantError.missingModel(provider.label)
        }

        guard !trimmedKey.isEmpty else {
            throw VisionAssistantError.missingAPIKey(provider.label)
        }

        switch provider {
        case .openAI:
            try await streamOpenAIResponse(
                model: trimmedModel,
                apiKey: trimmedKey,
                prompt: prompt,
                imageData: imageData,
                mimeType: mimeType,
                onDelta: onDelta
            )
        case .gemini:
            try await streamGeminiResponse(
                model: trimmedModel,
                apiKey: trimmedKey,
                prompt: prompt,
                imageData: imageData,
                mimeType: mimeType,
                onDelta: onDelta
            )
        }
    }

    private func streamOpenAIResponse(
        model: String,
        apiKey: String,
        prompt: String,
        imageData: Data?,
        mimeType: String?,
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws {
        var content: [[String: Any]] = [
            [
                "type": "input_text",
                "text": prompt,
            ],
        ]

        if let imageData, let mimeType {
            let imageURL = "data:\(mimeType);base64,\(imageData.base64EncodedString())"
            content.append(
                [
                    "type": "input_image",
                    "image_url": imageURL,
                ]
            )
        }

        let payload: [String: Any] = [
            "model": model,
            "stream": true,
            "input": [
                [
                    "role": "user",
                    "content": content,
                ],
            ],
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        var emittedText = false
        try await consumeSSE(from: request, provider: .openAI, model: model) { eventData in
            guard eventData != "[DONE]" else {
                return
            }

            guard let json = try JSONSerialization.jsonObject(with: Data(eventData.utf8)) as? [String: Any] else {
                return
            }

            if let error = (json["error"] as? [String: Any])?["message"] as? String {
                throw VisionAssistantError.serviceError(error)
            }

            let eventType = json["type"] as? String
            let delta = openAIDelta(from: json, eventType: eventType)
            if !delta.isEmpty {
                emittedText = true
                onDelta(delta)
            }
        }

        guard emittedText else {
            throw VisionAssistantError.emptyResponse
        }
    }

    private func streamGeminiResponse(
        model: String,
        apiKey: String,
        prompt: String,
        imageData: Data?,
        mimeType: String?,
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws {
        var parts: [[String: Any]] = [["text": prompt]]
        if let imageData, let mimeType {
            parts.append(
                [
                    "inline_data": [
                        "mime_type": mimeType,
                        "data": imageData.base64EncodedString(),
                    ],
                ]
            )
        }

        let payload: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": parts,
                ],
            ],
        ]

        var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VisionAssistantError.serviceError("응답 정보를 확인할 수 없습니다.")
        }

        if !(200 ..< 300).contains(httpResponse.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "응답 본문 없음"
            throw friendlyHTTPError(
                statusCode: httpResponse.statusCode,
                message: message,
                provider: .gemini,
                model: model
            )
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let raw = String(data: data, encoding: .utf8) ?? "응답 디코딩 실패"
            throw VisionAssistantError.serviceError("Gemini 응답 형식을 해석하지 못했습니다. 원본 응답: \(raw)")
        }

        if let error = json["error"] as? [String: Any] {
            let message = (error["message"] as? String) ?? "Gemini 요청에 실패했습니다."
            throw VisionAssistantError.serviceError(message)
        }

        if
            let promptFeedback = json["promptFeedback"] as? [String: Any],
            let blockReason = promptFeedback["blockReason"] as? String
        {
            throw VisionAssistantError.serviceError("Gemini가 요청을 차단했습니다: \(blockReason)")
        }

        let text = geminiDelta(from: json)
        guard !text.isEmpty else {
            throw VisionAssistantError.emptyResponse
        }

        onDelta(text)
    }

    private func consumeSSE(
        from request: URLRequest,
        provider: AIProvider,
        model: String,
        onEvent: (String) throws -> Void
    ) async throws {
        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VisionAssistantError.serviceError("응답 정보를 확인할 수 없습니다.")
        }

        if !(200 ..< 300).contains(httpResponse.statusCode) {
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
            }

            let message = String(data: body, encoding: .utf8) ?? "응답 본문 없음"
            throw friendlyHTTPError(
                statusCode: httpResponse.statusCode,
                message: message,
                provider: provider,
                model: model
            )
        }

        var eventLines: [String] = []

        for try await line in bytes.lines {
            try Task.checkCancellation()
            if line.isEmpty {
                let payload = eventLines.joined(separator: "\n")
                eventLines.removeAll(keepingCapacity: true)
                if !payload.isEmpty {
                    try onEvent(payload)
                }
                continue
            }

            guard line.hasPrefix("data:") else {
                continue
            }

            let rawValue = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            eventLines.append(rawValue)
        }

        if !eventLines.isEmpty {
            try onEvent(eventLines.joined(separator: "\n"))
        }
    }

    private func friendlyHTTPError(
        statusCode: Int,
        message: String,
        provider: AIProvider,
        model: String
    ) -> VisionAssistantError {
        let compactMessage = message
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedMessage = parsedServiceMessage(from: compactMessage) ?? compactMessage

        if provider == .gemini {
            let normalizedCompactMessage = compactMessage.lowercased()
            let normalizedParsedMessage = parsedMessage.lowercased()

            if
                statusCode == 400,
                normalizedCompactMessage.contains("api_key_invalid") || normalizedParsedMessage.contains("api key not valid")
            {
                return .httpError(statusCode, "Gemini API 키가 유효하지 않습니다. 선택한 키 슬롯을 다시 확인하세요.")
            }

            if statusCode == 404 {
                return .httpError(statusCode, "Gemini 모델 '\(model)'을 찾지 못했습니다. 설정의 모델명을 확인하세요.")
            }
        }

        return .httpError(statusCode, parsedMessage)
    }

    private func parsedServiceMessage(from message: String) -> String? {
        guard
            let data = message.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        if let error = json["error"] as? [String: Any] {
            if
                let parsedMessage = error["message"] as? String,
                !parsedMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                return parsedMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            if let status = error["status"] as? String, !status.isEmpty {
                return status
            }
        }

        return nil
    }

    private func openAIDelta(from json: [String: Any], eventType: String?) -> String {
        if eventType == "response.output_text.delta", let delta = json["delta"] as? String {
            return delta
        }

        if eventType == "response.output_text.done", let text = json["text"] as? String {
            return text
        }

        if let delta = json["delta"] as? String {
            return delta
        }

        return ""
    }

    private func geminiDelta(from json: [String: Any]) -> String {
        guard let candidates = json["candidates"] as? [[String: Any]] else {
            return ""
        }

        return candidates
            .compactMap { candidate -> String? in
                guard
                    let content = candidate["content"] as? [String: Any],
                    let parts = content["parts"] as? [[String: Any]]
                else {
                    return nil
                }

                return parts
                    .compactMap { $0["text"] as? String }
                    .joined()
            }
            .joined()
    }
}
