import Foundation

/// Nextcloud server discovery and Login Flow v2 (browser sign-in that returns an app password).
/// https://docs.nextcloud.com/server/latest/developer_manual/client_apis/LoginFlow/index.html
public enum NextcloudServer {
    /// Shown in Nextcloud's Security › Devices & sessions list.
    public static let userAgent = "Audio Pencil (macOS)"

    public struct Status: Decodable, Sendable, Equatable {
        public var installed: Bool
        public var maintenance: Bool?
        public var productname: String?
        public var versionstring: String?
    }

    public struct LoginStart: Sendable, Equatable {
        public var loginURL: URL
        public var pollEndpoint: URL
        public var token: String
    }

    public struct Credentials: Sendable, Equatable {
        public var account: NextcloudAccount
        public var appPassword: String

        public init(account: NextcloudAccount, appPassword: String) {
            self.account = account
            self.appPassword = appPassword
        }
    }

    /// Accepts what people paste: "cloud.example.com", "https://cloud.example.com/apps/files/",
    /// "https://example.com/nextcloud/index.php/login". Returns the server base URL.
    public static func normalise(_ input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard var components = URLComponents(string: text), let host = components.host, !host.isEmpty else { return nil }
        var path = components.path
        for marker in ["/index.php", "/remote.php", "/apps/", "/ocs/", "/login"] {
            if let range = path.range(of: marker) {
                path = String(path[..<range.lowerBound])
            }
        }
        while path.hasSuffix("/") { path.removeLast() }
        components.path = path
        components.query = nil
        components.fragment = nil
        return components.url
    }

    /// GET status.php: confirms the address is a Nextcloud server and reports its version.
    public static func status(of server: URL, session: URLSession = .shared) async throws -> Status {
        var request = URLRequest(url: server.appending(path: "status.php"))
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        let (data, response) = try await load(request, session: session)
        guard response.statusCode == 200, let status = try? JSONDecoder().decode(Status.self, from: data), status.installed else {
            throw StorageError.invalidServer(String(localized: "That address doesn't look like a Nextcloud server.", bundle: .module))
        }
        if status.maintenance == true {
            throw StorageError.invalidServer(String(localized: "The server is in maintenance mode. Try again later.", bundle: .module))
        }
        return status
    }

    /// Starts Login Flow v2. Open `loginURL` in the browser, then `waitForLogin`.
    public static func startLogin(server: URL, session: URLSession = .shared) async throws -> LoginStart {
        var request = URLRequest(url: server.appending(path: "index.php/login/v2"))
        request.httpMethod = "POST"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await load(request, session: session)
        guard response.statusCode == 200 else { throw StorageError.server(status: response.statusCode) }
        struct Body: Decodable {
            struct Poll: Decodable { var token: String; var endpoint: URL }
            var poll: Poll
            var login: URL
        }
        guard let body = try? JSONDecoder().decode(Body.self, from: data) else {
            throw StorageError.invalidServer(String(localized: "The server didn't start a sign-in.", bundle: .module))
        }
        return LoginStart(loginURL: body.login, pollEndpoint: body.poll.endpoint, token: body.poll.token)
    }

    /// Polls until the user approves in the browser (404 means "not yet"). Cancel the task to stop.
    public static func waitForLogin(
        _ start: LoginStart,
        session: URLSession = .shared,
        interval: Duration = .seconds(2),
        timeout: Duration = .seconds(20 * 60)
    ) async throws -> Credentials {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            var request = URLRequest(url: start.pollEndpoint)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            var form = URLComponents()
            form.queryItems = [URLQueryItem(name: "token", value: start.token)]
            request.httpBody = Data((form.percentEncodedQuery ?? "").utf8)
            let (data, response) = try await load(request, session: session)
            if response.statusCode == 200 {
                return try parseCredentials(data)
            }
            try await Task.sleep(for: interval)
        }
        throw StorageError.invalidServer(String(localized: "Sign-in timed out. Start again.", bundle: .module))
    }

    static func parseCredentials(_ data: Data) throws -> Credentials {
        struct Body: Decodable { var server: String; var loginName: String; var appPassword: String }
        guard let body = try? JSONDecoder().decode(Body.self, from: data), let server = normalise(body.server) else {
            throw StorageError.invalidServer(String(localized: "The server's sign-in reply was unreadable.", bundle: .module))
        }
        return Credentials(account: NextcloudAccount(server: server, loginName: body.loginName), appPassword: body.appPassword)
    }

    /// Checks an app password by listing the user's root folder.
    public static func verify(_ credentials: Credentials, session: URLSession = .shared) async throws {
        let storage = WebDAVStorage(account: credentials.account, appPassword: credentials.appPassword, session: session)
        _ = try await storage.item(at: "/")
    }

    private static func load(_ request: URLRequest, session: URLSession) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw StorageError.transport("No HTTP response") }
            return (data, http)
        } catch let error as StorageError {
            throw error
        } catch {
            throw StorageError.transport(error.localizedDescription)
        }
    }
}

extension NextcloudServer {
    /// Revokes an app password on the server (what "Sign out" should do, so it doesn't linger
    /// under Devices & sessions). Best effort.
    public static func revoke(_ credentials: Credentials, session: URLSession = .shared) async {
        var request = URLRequest(url: credentials.account.server.appending(path: "ocs/v2.php/core/apppassword"))
        request.httpMethod = "DELETE"
        request.setValue("true", forHTTPHeaderField: "OCS-APIRequest")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let basic = Data("\(credentials.account.loginName):\(credentials.appPassword)".utf8).base64EncodedString()
        request.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        _ = try? await session.data(for: request)
    }
}
