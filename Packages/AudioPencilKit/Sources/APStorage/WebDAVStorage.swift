import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// A signed-in Nextcloud account. The app password lives in the Keychain, not here.
public struct NextcloudAccount: Codable, Equatable, Hashable, Sendable {
    /// Server base URL, e.g. https://cloud.example.com or https://example.com/nextcloud
    public var server: URL
    public var loginName: String

    public init(server: URL, loginName: String) {
        self.server = server
        self.loginName = loginName
    }

    /// WebDAV root for the user's files.
    public var davRoot: URL {
        server.appending(path: "remote.php/dav/files", directoryHint: .isDirectory)
            .appending(path: loginName, directoryHint: .isDirectory)
    }
}

/// Nextcloud files over WebDAV. Paths are relative to the user's files root ("/" = Files home).
public final class WebDAVStorage: StorageProvider {
    public let account: NextcloudAccount
    private let password: String
    private let session: URLSession

    public init(account: NextcloudAccount, appPassword: String, session: URLSession = .shared) {
        self.account = account
        self.password = appPassword
        self.session = session
    }

    public func list(_ path: String) async throws -> [StorageItem] {
        let items = try await propfind(path, depth: "1")
        let normalised = StoragePath.join(path)
        return items.filter { $0.path != normalised }
    }

    public func item(at path: String) async throws -> StorageItem? {
        do {
            return try await propfind(path, depth: "0").first
        } catch StorageError.notFound {
            return nil
        }
    }

    public func read(_ path: String) async throws -> (data: Data, etag: String?) {
        let (data, response) = try await send(request(path, method: "GET"), path: path)
        return (data, response.value(forHTTPHeaderField: "ETag"))
    }

    @discardableResult
    public func write(_ path: String, data: Data, ifMatch: String?, createOnly: Bool) async throws -> String? {
        var request = request(path, method: "PUT")
        request.httpBody = data
        if let ifMatch { request.setValue(ifMatch, forHTTPHeaderField: "If-Match") }
        if createOnly { request.setValue("*", forHTTPHeaderField: "If-None-Match") }
        let (_, response) = try await send(request, path: path)
        return response.value(forHTTPHeaderField: "ETag") ?? response.value(forHTTPHeaderField: "OC-ETag")
    }

    public func createFolder(_ path: String) async throws {
        do {
            _ = try await send(request(path, method: "MKCOL", folder: true), path: path)
        } catch StorageError.server(status: 405) {
            // Already exists.
        }
    }

    public func delete(_ path: String) async throws {
        do {
            _ = try await send(request(path, method: "DELETE"), path: path)
        } catch StorageError.notFound {
            // Already gone.
        }
    }

    // MARK: Requests

    func url(for path: String, folder: Bool = false) -> URL {
        var url = account.davRoot
        let components = path.split(separator: "/").map(String.init)
        for (index, component) in components.enumerated() {
            let isLast = index == components.count - 1
            url = url.appending(path: component, directoryHint: isLast && !folder ? .notDirectory : .isDirectory)
        }
        return url
    }

    private func request(_ path: String, method: String, folder: Bool = false) -> URLRequest {
        var request = URLRequest(url: url(for: path, folder: folder))
        request.httpMethod = method
        let credentials = Data("\(account.loginName):\(password)".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        request.setValue(NextcloudServer.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30
        return request
    }

    private func propfind(_ path: String, depth: String) async throws -> [StorageItem] {
        var request = request(path, method: "PROPFIND", folder: true)
        request.setValue(depth, forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("""
            <?xml version="1.0" encoding="utf-8"?>
            <d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/><d:getetag/><d:getlastmodified/><d:getcontentlength/></d:prop></d:propfind>
            """.utf8)
        let (data, _) = try await send(request, path: path)
        return try MultistatusParser.parse(data, davRootPath: account.davRoot.path(percentEncoded: false))
    }

    private func send(_ request: URLRequest, path: String) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw StorageError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw StorageError.transport("No HTTP response") }
        switch http.statusCode {
        case 200..<300: return (data, http)
        case 401, 403: throw StorageError.unauthorized
        case 404: throw StorageError.notFound(path)
        case 412: throw StorageError.conflict(path)
        case 507: throw StorageError.storageFull
        default: throw StorageError.server(status: http.statusCode)
        }
    }
}

/// Parses a WebDAV PROPFIND multistatus response into items with paths relative to the DAV root.
enum MultistatusParser {
    static func parse(_ data: Data, davRootPath: String) throws -> [StorageItem] {
        let delegate = Delegate(rootPath: davRootPath)
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        guard parser.parse() else {
            throw StorageError.invalidServer("Couldn't read the server's folder listing.")
        }
        return delegate.items
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        let rootPath: String
        var items: [StorageItem] = []
        private var text = ""
        private var href: String?
        private var isCollection = false
        private var etag: String?
        private var size: Int?
        private var modified: Date?

        private static let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "GMT")
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            return formatter
        }()

        init(rootPath: String) {
            self.rootPath = rootPath.hasSuffix("/") ? String(rootPath.dropLast()) : rootPath
        }

        func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            text = ""
            switch element {
            case "response":
                href = nil; isCollection = false; etag = nil; size = nil; modified = nil
            case "collection":
                isCollection = true
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch element {
            case "href": href = value
            case "getetag": etag = value.isEmpty ? nil : value
            case "getcontentlength": size = Int(value)
            case "getlastmodified": modified = Self.dateFormatter.date(from: value)
            case "response":
                if let href, let path = relativePath(fromHref: href) {
                    items.append(StorageItem(path: path, isFolder: isCollection, etag: etag, size: size, modified: modified))
                }
            default:
                break
            }
            text = ""
        }

        /// "/remote.php/dav/files/wes/Obsidian%20Vault/" → "/Obsidian Vault"
        private func relativePath(fromHref href: String) -> String? {
            var path = href
            if let url = URL(string: href), url.host() != nil {
                path = url.path(percentEncoded: true)
            }
            guard let decoded = path.removingPercentEncoding else { return nil }
            guard let range = decoded.range(of: rootPath) else { return nil }
            return StoragePath.join(String(decoded[range.upperBound...]))
        }
    }
}
