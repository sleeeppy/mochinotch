import Foundation
import Network

/// 루프백 전용 `POST /event`. hook 스크립트가 curl로 상태를 보낸다.
final class EventServer {
    var onEvent: ((IncomingEvent) -> Void)?
    var onFailure: ((String) -> Void)?
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "dev.sleeeppy.mochinotch.events")

    func start(port: UInt16) {
        do {
            let parameters = NWParameters.tcp
            parameters.requiredInterfaceType = .loopback
            parameters.allowLocalEndpointReuse = true
            guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
            let listener = try NWListener(using: parameters, on: nwPort)
            listener.newConnectionHandler = { [weak self] connection in
                self?.receive(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed(let error) = state {
                    DispatchQueue.main.async {
                        self?.onFailure?(error.localizedDescription)
                    }
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.onFailure?(error.localizedDescription)
            }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func receive(_ connection: NWConnection) {
        connection.start(queue: queue)
        read(connection, into: Data())
    }

    private func read(_ connection: NWConnection, into buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var next = buffer
            if let data {
                next.append(data)
            }
            if self.httpBody(in: next) != nil || isComplete || error != nil || next.count > 60_000 {
                self.handle(next, connection: connection)
                return
            }
            self.read(connection, into: next)
        }
    }

    private func handle(_ data: Data, connection: NWConnection) {
        if let body = httpBody(in: data) ?? rawJSON(data),
           let event = try? JSONDecoder().decode(IncomingEvent.self, from: body) {
            DispatchQueue.main.async { [onEvent] in
                onEvent?(event)
            }
        }
        let response = "HTTP/1.1 204 No Content\r\nConnection: close\r\nContent-Length: 0\r\n\r\n"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func rawJSON(_ data: Data) -> Data? {
        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              text.hasPrefix("{")
        else { return nil }
        return Data(text.utf8)
    }

    private func httpBody(in data: Data) -> Data? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        guard let headerEnd = text.range(of: "\r\n\r\n") else { return nil }
        let header = text[..<headerEnd.lowerBound]
        let body = text[headerEnd.upperBound...]
        if !header.uppercased().contains("POST ") {
            return nil
        }
        if let length = contentLength(in: String(header)) {
            guard body.utf8.count >= length else { return nil }
            let payload = String(body.prefix(length))
            return Data(payload.utf8)
        }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") else { return nil }
        return Data(trimmed.utf8)
    }

    private func contentLength(in header: String) -> Int? {
        for line in header.split(separator: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" else {
                continue
            }
            return Int(parts[1].trimmingCharacters(in: .whitespaces))
        }
        return nil
    }
}

struct IncomingEvent: Decodable, Equatable {
    /// 같은 작업에 hook이 두 번 불려도 한 번만 보이게 하는 키. 없으면 내용으로 가린다.
    var id: String?
    var tool: String?
    var title: String?
    var detail: String?
    var success: Bool?
    var kind: String?
    var bundleID: String?
}
