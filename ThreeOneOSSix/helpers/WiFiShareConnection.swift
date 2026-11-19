import Foundation
import Network

/// One HTTP connection against `WiFiShareServer`.
///
/// Deliberately single-request: every response carries `Connection: close` and
/// the socket is cancelled afterwards. Keep-alive would save a TCP handshake on
/// a LAN, and cost a state machine whose pipelining edge cases are far more
/// likely to produce a hang than the handshake is to cost the user anything.
final class WiFiShareConnection {
    private let connection: NWConnection
    private let rootURL: URL
    private let pin: String
    private let onRequest: (String) -> Void
    private let onFinish: (ObjectIdentifier) -> Void

    private var buffer = Data()
    private var headersParsed = false
    private var finished = false

    /// Cap on the request head. A path plus a handful of headers is well under
    /// this; anything larger is a malformed request or an attempt to exhaust
    /// memory through the header parser.
    private static let maximumHeaderBytes = 32 * 1024

    init(
        connection: NWConnection,
        rootURL: URL,
        pin: String,
        onRequest: @escaping (String) -> Void,
        onFinish: @escaping (ObjectIdentifier) -> Void
    ) {
        self.connection = connection
        self.rootURL = rootURL
        self.pin = pin
        self.onRequest = onRequest
        self.onFinish = onFinish
    }

    private var identifier: ObjectIdentifier { ObjectIdentifier(self) }

    func start(on queue: DispatchQueue) {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .failed, .cancelled:
                self.finishOnce()
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive()
    }

    func cancel() {
        connection.cancel()
        finishOnce()
    }

    private func finishOnce() {
        guard !finished else { return }
        finished = true
        onFinish(identifier)
    }

    // MARK: - Receive loop

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                if !self.headersParsed {
                    self.tryParseHeaders()
                } else {
                    self.continueUpload()
                }
            }
            if error != nil || isComplete {
                self.finishOnce()
                return
            }
            if !self.finished {
                self.receive()
            }
        }
    }

    private func tryParseHeaders() {
        guard let separator = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            if buffer.count > Self.maximumHeaderBytes {
                respond(status: 431, text: "Request header too large")
            }
            return
        }
        let headData = buffer.subdata(in: buffer.startIndex..<separator.lowerBound)
        let bodyStart = separator.upperBound
        // Keep whatever body bytes arrived with the head; uploads stream from
        // there and never re-request them.
        let leftover = buffer.subdata(in: bodyStart..<buffer.endIndex)
        buffer = leftover

        guard let head = String(data: headData, encoding: .utf8) else {
            respond(status: 400, text: "Malformed request")
            return
        }
        let lines = head.components(separatedBy: "\r\n")
        guard let requestLineText = lines.first,
              let requestLine = WiFiSharePolicy.parseRequestLine(requestLineText) else {
            respond(status: 400, text: "Malformed request line")
            return
        }
        let headerText = lines.dropFirst().joined(separator: "\r\n")
        headersParsed = true
        onRequest("\(requestLine.method) \(requestLine.target)")

        // Auth before anything else: a 401 must not leak whether a path exists.
        guard WiFiSharePolicy.isAuthorized(
            header: WiFiSharePolicy.authorizationHeader(in: headerText),
            pin: pin
        ) else {
            respond(
                status: 401,
                text: "Authentication required",
                extraHeaders: ["WWW-Authenticate": "Basic realm=\"\(WiFiSharePolicy.realm)\""]
            )
            return
        }

        switch (requestLine.method, requestLine.path) {
        case ("GET", "/"):
            respondDirectoryListing()
        case ("GET", "/api/download"):
            handleDownload(query: requestLine.query)
        case ("GET", "/api/zip"):
            handleZip(query: requestLine.query)
        case ("PUT", "/api/upload"):
            beginUpload(query: requestLine.query, headers: headerText)
        case ("POST", "/api/upload"):
            beginUpload(query: requestLine.query, headers: headerText)
        default:
            respond(status: 404, text: "Not found")
        }
    }

    // MARK: - Response

    /// Builds the response head. Separated from the send so a file response can
/// declare `Content-Length` up front and then stream, instead of buffering.
    private func responseHead(
        status: Int,
        contentType: String,
        length: Int,
        extraHeaders: [String: String] = [:]
    ) -> String {
        var head = "HTTP/1.1 \(status) \(Self.reason(status))\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(length)\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "Connection: close\r\n"
        for (key, value) in extraHeaders {
            head += "\(key): \(value)\r\n"
        }
        head += "\r\n"
        return head
    }

    private func respond(
        status: Int,
        text: String,
        contentType: String = "text/plain; charset=utf-8",
        extraHeaders: [String: String] = [:],
        body: Data? = nil
    ) {
        let payload = body ?? Data(text.utf8)
        let head = responseHead(
            status: status,
            contentType: contentType,
            length: payload.count,
            extraHeaders: extraHeaders
        )
        var out = Data(head.utf8)
        out.append(payload)
        send(out) { [weak self] in
            self?.closeAfterResponse()
        }
    }

    private func send(_ data: Data, completion: @escaping () -> Void) {
        connection.send(content: data, completion: .contentProcessed { _ in
            completion()
        })
    }

    /// Sends a head plus a file's contents chunk by chunk. The file length must
    /// already be known: `Content-Length` goes out before the first chunk, so a
    /// response cannot be renegotiated mid-stream.
    private func sendFile(
        _ fileURL: URL,
        byteCount: Int,
        head: String,
        completion: @escaping () -> Void
    ) {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            respond(status: 500, text: "Could not read file")
            return
        }
        send(Data(head.utf8)) { [weak self] in
            guard let self else { try? handle.close(); return }
            self.pumpFile(handle, remaining: byteCount, completion: completion)
        }
    }

    private func pumpFile(
        _ handle: FileHandle,
        remaining: Int,
        completion: @escaping () -> Void
    ) {
        guard remaining > 0 else {
            try? handle.close()
            completion()
            return
        }
        let want = min(remaining, WiFiSharePolicy.uploadChunkBytes)
        guard let chunk = try? handle.read(upToCount: want), !chunk.isEmpty else {
            // Short read: the head already promised more than the file holds.
            // Closing the connection is the only honest signal left.
            try? handle.close()
            connection.cancel()
            finishOnce()
            return
        }
        connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
            guard let self else { try? handle.close(); return }
            if error != nil {
                try? handle.close()
                self.finishOnce()
                return
            }
            self.pumpFile(handle, remaining: remaining - chunk.count, completion: completion)
        })
    }

    private func closeAfterResponse() {
        connection.cancel()
        finishOnce()
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 409: return "Conflict"
        case 413: return "Payload Too Large"
        case 431: return "Request Header Fields Too Large"
        case 500: return "Internal Server Error"
        default:  return "Status"
        }
    }

    // MARK: - GET /

    private func respondDirectoryListing() {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey]
        )) ?? []
        let sorted = entries.sorted { $0.lastPathComponent < $1.lastPathComponent }

        var rows = ""
        for url in sorted {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            let isDirectory = values?.isDirectory == true
            let name = url.lastPathComponent
            let size = isDirectory
                ? "—"
                : ByteCountFormatter.string(fromByteCount: Int64(values?.fileSize ?? 0),
                                            countStyle: .file)
            let href = "/api/" + (isDirectory ? "zip" : "download")
                + "?path=" + Self.percentEncode(name)
            rows += """
            <tr><td><a href="\(Self.htmlEscape(href))">\(Self.htmlEscape(name))\
            \(isDirectory ? "/" : "")</a></td><td>\(Self.htmlEscape(size))</td></tr>

            """
        }

        let html = """
        <!doctype html><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <title>3106 · Transfer</title>
        <style>
        body{font:16px -apple-system,sans-serif;margin:2rem auto;max-width:44rem;padding:0 1rem}
        table{width:100%;border-collapse:collapse}
        td{padding:.5rem .25rem;border-bottom:1px solid #ddd}
        td:last-child{text-align:right;color:#666;white-space:nowrap}
        a{color:#0a84ff;text-decoration:none}
        code{background:#f2f2f7;padding:.15rem .35rem;border-radius:4px}
        </style>
        <h1>3106 · Transfer</h1>
        <p>Upload: <code>curl -u 3106:PIN -T file http://HOST:PORT/api/upload?path=file</code></p>
        <table>\(rows)</table>
        """
        respond(status: 200, text: html, contentType: "text/html; charset=utf-8")
    }

    // MARK: - GET /api/download

    private func handleDownload(query: String) {
        guard let raw = WiFiSharePolicy.queryParameter("path", in: query),
              let url = WiFiSharePolicy.containedPath(raw, within: rootURL) else {
            respond(status: 403, text: "Path outside the transfer folder")
            return
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else {
            respond(status: 404, text: "File not found")
            return
        }
        // Streamed, not loaded: a 1 GB file in Documents is a normal thing to
        // want to pull off a phone, and reading it into memory first would
        // fail exactly when the feature is most useful.
        let head = responseHead(
            status: 200,
            contentType: "application/octet-stream",
            length: size,
            extraHeaders: ["Content-Disposition": "attachment; filename=\"\(url.lastPathComponent)\""]
        )
        sendFile(url, byteCount: size, head: head) { [weak self] in
            self?.closeAfterResponse()
        }
    }

    // MARK: - GET /api/zip

    private func handleZip(query: String) {
        guard let raw = WiFiSharePolicy.queryParameter("path", in: query),
              let url = WiFiSharePolicy.containedPath(raw, within: rootURL) else {
            respond(status: 403, text: "Path outside the transfer folder")
            return
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            respond(status: 404, text: "Folder not found")
            return
        }
        guard isDirectory.boolValue else {
            respond(status: 400, text: "Not a folder")
            return
        }

        // Build to a temp file, then stream it: holding a 2 GB archive in memory
        // would terminate the app before the headers went out.
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("wifi-share-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: staging) }

        do {
            let result = try ZIPArchiveWriter.write(items: [url], to: staging)
            let values = try staging.resourceValues(forKeys: [.fileSizeKey])
            let size = values.fileSize ?? 0
            guard size <= WiFiSharePolicy.maximumZipBytes else {
                respond(status: 413, text: "Archive exceeds 2 GB")
                return
            }
            guard result.entryCount > 0 else {
                respond(status: 400, text: "Folder is empty")
                return
            }
            let head = responseHead(
                status: 200,
                contentType: "application/zip",
                length: size,
                extraHeaders: [
                    "Content-Disposition":
                        "attachment; filename=\"\(url.lastPathComponent).zip\"",
                ]
            )
            sendFile(staging, byteCount: size, head: head) { [weak self] in
                self?.closeAfterResponse()
            }
        } catch {
            respond(status: 500, text: "Could not build archive")
        }
    }

    // MARK: - PUT /api/upload

    private var uploadTarget: URL?
    private var uploadPartURL: URL?
    private var uploadHandle: FileHandle?
    private var uploadRemaining: Int?

    private func beginUpload(query: String, headers: String) {
        guard let raw = WiFiSharePolicy.queryParameter("path", in: query),
              let url = WiFiSharePolicy.containedPath(raw, within: rootURL) else {
            respond(status: 403, text: "Path outside the transfer folder")
            return
        }
        guard let length = WiFiSharePolicy.contentLength(in: headers), length >= 0 else {
            // A streaming upload without Content-Length would need chunked
            // decoding; refusing is honest and keeps the parser small.
            respond(status: 400, text: "Content-Length required")
            return
        }

        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Never overwrite: pick a free name, then write beside it as `.part` so
        // a dropped connection leaves no half-file under the real name.
        let directory = url.deletingLastPathComponent()
        let requested = url.lastPathComponent
        let chosen = WiFiSharePolicy.uniqueDestination(for: requested) {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
        let destination = directory.appendingPathComponent(chosen)
        let part = directory.appendingPathComponent(".\(chosen).part")
        try? FileManager.default.removeItem(at: part)
        guard FileManager.default.createFile(atPath: part.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: part) else {
            respond(status: 500, text: "Could not create file")
            return
        }

        uploadTarget = destination
        uploadPartURL = part
        uploadHandle = handle
        uploadRemaining = length

        if length == 0 {
            finishUpload()
            return
        }
        // Body bytes that arrived alongside the header block.
        continueUpload()
    }

    private func continueUpload() {
        guard let handle = uploadHandle else { return }
        if !buffer.isEmpty {
            let chunk = buffer
            buffer.removeAll(keepingCapacity: true)
            do {
                try handle.write(contentsOf: chunk)
            } catch {
                abortUpload(status: 500, text: "Write failed")
                return
            }
            if let remaining = uploadRemaining {
                uploadRemaining = max(0, remaining - chunk.count)
            }
        }
        if let remaining = uploadRemaining, remaining <= 0 {
            finishUpload()
        }
    }

    private func finishUpload() {
        try? uploadHandle?.close()
        uploadHandle = nil
        guard let part = uploadPartURL, let destination = uploadTarget else { return }
        do {
            // Atomic rename within the same directory: a reader either sees the
            // complete file or none at all.
            try FileManager.default.moveItem(at: part, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: part)
            respond(status: 500, text: "Could not finalize upload")
            return
        }
        uploadPartURL = nil
        uploadTarget = nil
        respond(status: 201, text: "Uploaded as \(destination.lastPathComponent)")
    }

    private func abortUpload(status: Int, text: String) {
        try? uploadHandle?.close()
        uploadHandle = nil
        if let part = uploadPartURL { try? FileManager.default.removeItem(at: part) }
        uploadPartURL = nil
        uploadTarget = nil
        respond(status: status, text: text)
    }

    // MARK: - Encoding helpers

    private static func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+#?")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func htmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}