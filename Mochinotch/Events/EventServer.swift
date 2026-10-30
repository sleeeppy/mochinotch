import Foundation
import Network

/// 루프백 전용 `POST /event`. hook이 토큰을 붙여 상태를 보낸다.
final class EventServer {
    var onEvent: ((IncomingEvent) -> Void)?
    var onFailure: ((String) -> Void)?
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "dev.sleeeppy.mochinotch.events")

    func start(port: UInt16) {
        _ = EventToken.loadOrCreate()
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
            let finished = isComplete || error != nil
            switch EventHTTP.parse(next, complete: finished) {
            case .needMore:
                if finished || next.count > 60_000 {
                    self.finish(connection, status: 400)
                    return
                }
                self.read(connection, into: next)
            case .reject:
                self.finish(connection, status: 400)
            case .event(let body, let token):
                guard EventToken.accepts(token),
                      let event = try? JSONDecoder().decode(IncomingEvent.self, from: body) else {
                    self.finish(connection, status: 401)
                    return
                }
                DispatchQueue.main.async { [onEvent] in
                    onEvent?(event)
                }
                self.finish(connection, status: 204)
            }
        }
    }

    private func finish(_ connection: NWConnection, status: Int) {
        let reason = status == 204 ? "No Content" : (status == 401 ? "Unauthorized" : "Bad Request")
        let response = "HTTP/1.1 \(status) \(reason)\r\nConnection: close\r\nContent-Length: 0\r\n\r\n"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

/// `POST /event`만 받는다. 본문 길이는 바이트로 자르고, 음수 길이는 거절한다.
enum EventHTTP {
    enum Result: Equatable {
        case needMore
        case reject
        case event(Data, token: String)
    }

    static func parse(_ data: Data, complete: Bool) -> Result {
        let separator = Data([13, 10, 13, 10])
        guard let headerEnd = data.range(of: separator) else {
            return data.count > 60_000 ? .reject : .needMore
        }
        let headerData = data[..<headerEnd.lowerBound]
        let body = data[headerEnd.upperBound...]
        guard let header = String(data: headerData, encoding: .utf8) else { return .reject }
        let lines = header.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let request = lines.first else { return .reject }
        let fields = request.split(separator: " ")
        guard fields.count >= 2,
              fields[0].uppercased() == "POST",
              fields[1].split(separator: "?").first.map(String.init) == "/event"
        else { return .reject }

        let token = headerValue(EventToken.headerName, in: lines.dropFirst()) ?? ""
        switch contentLength(in: lines.dropFirst()) {
        case .missing:
            guard complete else { return .needMore }
            guard body.first == UInt8(ascii: "{") else { return .reject }
            return .event(Data(body), token: token)
        case .invalid:
            return .reject
        case .value(let length):
            guard body.count >= length else { return complete ? .reject : .needMore }
            return .event(Data(body.prefix(length)), token: token)
        }
    }

    private enum Length {
        case missing
        case invalid
        case value(Int)
    }

    private static func contentLength(in lines: ArraySlice<Substring>) -> Length {
        var found: Int?
        for line in lines {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length"
            else { continue }
            let raw = parts[1].trimmingCharacters(in: .whitespaces)
            guard let length = Int(raw), length >= 0, length <= 60_000 else { return .invalid }
            if let found, found != length { return .invalid }
            found = length
        }
        if let found { return .value(found) }
        return .missing
    }

    private static func headerValue(_ name: String, in lines: ArraySlice<Substring>) -> String? {
        for line in lines {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespaces).lowercased() == name.lowercased()
            else { continue }
            return parts[1].trimmingCharacters(in: .whitespaces)
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
