@testable import APStorage
import Foundation
import Testing
import os

/// Simulated server. Each test's session carries its own handler (keyed by a header), so tests
/// running in parallel don't answer each other's requests.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest, Data?) -> (Int, [String: String], Data)

    final class Stub: Sendable {
        let handler: Handler
        let session: URLSession
        private let recorded = OSAllocatedUnfairLock<[(URLRequest, Data?)]>(initialState: [])
        var requests: [(URLRequest, Data?)] { recorded.withLock { $0 } }

        init(id: String, handler: @escaping Handler) {
            self.handler = handler
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [StubProtocol.self]
            configuration.httpAdditionalHeaders = ["X-Stub-ID": id]
            session = URLSession(configuration: configuration)
        }

        func record(_ request: URLRequest, _ body: Data?) { recorded.withLock { $0.append((request, body)) } }
    }

    static let stubs = OSAllocatedUnfairLock<[String: Stub]>(initialState: [:])

    static func make(_ handler: @escaping Handler) -> Stub {
        let id = UUID().uuidString
        let stub = Stub(id: id, handler: handler)
        stubs.withLock { $0[id] = stub }
        return stub
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = request.httpBody ?? request.httpBodyStream.map(Self.readAll)
        guard let id = request.value(forHTTPHeaderField: "X-Stub-ID"),
              let stub = Self.stubs.withLock({ $0[id] }), let url = request.url else { return }
        stub.record(request, body)
        let (status, headers, data) = stub.handler(request, body)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readAll(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private let account = NextcloudAccount(server: URL(string: "https://cloud.example.com")!, loginName: "wes")

private let listing = """
    <?xml version="1.0"?>
    <d:multistatus xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns">
     <d:response><d:href>/remote.php/dav/files/wes/Obsidian/</d:href>
      <d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype><d:getetag>"aaa"</d:getetag>
      <d:getlastmodified>Sun, 19 Oct 2026 14:00:00 GMT</d:getlastmodified></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
     <d:response><d:href>/remote.php/dav/files/wes/Obsidian/My%20Vault/</d:href>
      <d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype><d:getetag>"bbb"</d:getetag></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
     <d:response><d:href>/remote.php/dav/files/wes/Obsidian/notes%20%26%20ideas.md</d:href>
      <d:propstat><d:prop><d:resourcetype/><d:getetag>"ccc"</d:getetag><d:getcontentlength>42</d:getcontentlength></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
    </d:multistatus>
    """

struct NextcloudServerTests {
    @Test func normalisesPastedAddresses() {
        #expect(NextcloudServer.normalise("cloud.example.com")?.absoluteString == "https://cloud.example.com")
        #expect(NextcloudServer.normalise(" https://cloud.example.com/apps/files/?dir=/ ")?.absoluteString == "https://cloud.example.com")
        #expect(NextcloudServer.normalise("https://example.com/nextcloud/index.php/login")?.absoluteString == "https://example.com/nextcloud")
        #expect(NextcloudServer.normalise("http://192.168.1.5:8080/")?.absoluteString == "http://192.168.1.5:8080")
        #expect(NextcloudServer.normalise("") == nil)
    }

    @Test func statusRejectsNonNextcloud() async {
        let stub = StubProtocol.make { _, _ in (200, [:], Data("<html>hello</html>".utf8)) }
        await #expect(throws: StorageError.self) {
            _ = try await NextcloudServer.status(of: account.server, session: stub.session)
        }
    }

    @Test func statusReadsVersion() async throws {
        let stub = StubProtocol.make { _, _ in
            (200, [:], Data(#"{"installed":true,"maintenance":false,"productname":"Nextcloud","versionstring":"31.0.2"}"#.utf8))
        }
        let status = try await NextcloudServer.status(of: account.server, session: stub.session)
        #expect(status.versionstring == "31.0.2")
        #expect(stub.requests.first?.0.url?.absoluteString == "https://cloud.example.com/status.php")
    }

    @Test func loginFlowPollsUntilApproved() async throws {
        let polls = OSAllocatedUnfairLock(initialState: 0)
        let stub = StubProtocol.make { request, body in
            if request.url?.path == "/index.php/login/v2" {
                return (200, [:], Data(#"{"poll":{"token":"t0k","endpoint":"https://cloud.example.com/login/v2/poll"},"login":"https://cloud.example.com/login/v2/flow/abc"}"#.utf8))
            }
            #expect(String(data: body ?? Data(), encoding: .utf8) == "token=t0k")
            let count = polls.withLock { $0 += 1; return $0 }
            if count < 3 { return (404, [:], Data()) }
            return (200, [:], Data(#"{"server":"https://cloud.example.com","loginName":"wes","appPassword":"app-pw"}"#.utf8))
        }
        let start = try await NextcloudServer.startLogin(server: account.server, session: stub.session)
        #expect(start.loginURL.absoluteString == "https://cloud.example.com/login/v2/flow/abc")
        let credentials = try await NextcloudServer.waitForLogin(start, session: stub.session, interval: .milliseconds(10))
        #expect(credentials.account == account)
        #expect(credentials.appPassword == "app-pw")
        #expect(polls.withLock { $0 } == 3)
    }
}

struct WebDAVStorageTests {
    @Test func parsesListingWithEncodedNames() throws {
        let items = try MultistatusParser.parse(Data(listing.utf8), davRootPath: "/remote.php/dav/files/wes/")
        #expect(items.map(\.path) == ["/Obsidian", "/Obsidian/My Vault", "/Obsidian/notes & ideas.md"])
        #expect(items.map(\.isFolder) == [true, true, false])
        #expect(items[2].size == 42)
        #expect(items[0].modified != nil)
    }

    @Test func listSendsAuthenticatedPropfindAndDropsTheFolderItself() async throws {
        let stub = StubProtocol.make { _, _ in (207, [:], Data(listing.utf8)) }
        let storage = WebDAVStorage(account: account, appPassword: "pw", session: stub.session)
        let items = try await storage.list("/Obsidian")
        #expect(items.map(\.name) == ["My Vault", "notes & ideas.md"])

        let request = try #require(stub.requests.first?.0)
        #expect(request.httpMethod == "PROPFIND")
        #expect(request.value(forHTTPHeaderField: "Depth") == "1")
        #expect(request.url?.absoluteString == "https://cloud.example.com/remote.php/dav/files/wes/Obsidian/")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Basic " + Data("wes:pw".utf8).base64EncodedString())
    }

    @Test func urlsEncodeSpacesAndSpecialCharacters() {
        let storage = WebDAVStorage(account: account, appPassword: "pw")
        #expect(storage.url(for: "/My Vault/Daily #1.md").absoluteString == "https://cloud.example.com/remote.php/dav/files/wes/My%20Vault/Daily%20%231.md")
    }

    @Test func conditionalWriteMapsPreconditionFailedToConflict() async throws {
        let stub = StubProtocol.make { request, _ in
            request.value(forHTTPHeaderField: "If-Match") == "\"old\"" ? (412, [:], Data()) : (201, ["ETag": "\"new\""], Data())
        }
        let storage = WebDAVStorage(account: account, appPassword: "pw", session: stub.session)
        await #expect(throws: StorageError.conflict("/a.md")) {
            try await storage.write("/a.md", data: Data("x".utf8), ifMatch: "\"old\"", createOnly: false)
        }
        let etag = try await storage.write("/a.md", data: Data("x".utf8), ifMatch: nil, createOnly: true)
        #expect(etag == "\"new\"")
        #expect(stub.requests.last?.0.value(forHTTPHeaderField: "If-None-Match") == "*")
    }

    @Test func missingItemIsNilAndExistingFolderIsFine() async throws {
        let stub = StubProtocol.make { request, _ in
            request.httpMethod == "MKCOL" ? (405, [:], Data()) : (404, [:], Data())
        }
        let storage = WebDAVStorage(account: account, appPassword: "pw", session: stub.session)
        #expect(try await storage.item(at: "/nope") == nil)
        try await storage.createFolder("/Existing")
        try await storage.delete("/already-gone.md")
    }

    @Test func rejectedSignInIsUnauthorized() async {
        let stub = StubProtocol.make { _, _ in (401, [:], Data()) }
        let storage = WebDAVStorage(account: account, appPassword: "wrong", session: stub.session)
        await #expect(throws: StorageError.unauthorized) { _ = try await storage.list("/") }
    }
}

struct LocalFolderStorageTests {
    private func makeStorage() throws -> LocalFolderStorage {
        let root = FileManager.default.temporaryDirectory.appending(path: "audiopencil-local-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return LocalFolderStorage(root: root, usesTrash: false)
    }

    @Test func writeReadListAndDelete() async throws {
        let storage = try makeStorage()
        defer { try? FileManager.default.removeItem(at: storage.root) }
        let etag = try await storage.write("/Notes/Today.md", data: Data("hello".utf8), ifMatch: nil, createOnly: true)
        #expect(etag != nil)
        let (data, readTag) = try await storage.read("/Notes/Today.md")
        #expect(String(data: data, encoding: .utf8) == "hello")
        #expect(readTag == etag)
        #expect(try await storage.list("/Notes").map(\.path) == ["/Notes/Today.md"])
        #expect(try await storage.list("/").first?.isFolder == true)
        try await storage.delete("/Notes/Today.md")
        #expect(try await storage.item(at: "/Notes/Today.md") == nil)
    }

    @Test func staleEtagAndCreateOnlyConflict() async throws {
        let storage = try makeStorage()
        defer { try? FileManager.default.removeItem(at: storage.root) }
        let first = try await storage.write("/c.md", data: Data("1".utf8), ifMatch: nil, createOnly: false)
        try await Task.sleep(for: .milliseconds(20))
        _ = try await storage.write("/c.md", data: Data("22".utf8), ifMatch: first, createOnly: false)
        await #expect(throws: StorageError.conflict("/c.md")) {
            try await storage.write("/c.md", data: Data("3".utf8), ifMatch: first, createOnly: false)
        }
        await #expect(throws: StorageError.conflict("/c.md")) {
            try await storage.write("/c.md", data: Data("3".utf8), ifMatch: nil, createOnly: true)
        }
    }

    @Test func pathHelpers() {
        #expect(StoragePath.join("/a/", "b", "c.md") == "/a/b/c.md")
        #expect(StoragePath.join("/") == "/")
        #expect(StoragePath.parent(of: "/a/b") == "/a")
        #expect(StoragePath.parent(of: "/a") == "/")
    }
}
