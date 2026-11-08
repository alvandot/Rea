import Foundation
#if canImport(JavaScriptCore)
import JavaScriptCore
#endif

public struct ExtensionManifest: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var version: String
    public var language: String
    public var entry: String
    public var description: String?

    public init(
        id: String,
        name: String,
        version: String,
        language: String = "en",
        entry: String = "source.js",
        description: String? = nil
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.language = language
        self.entry = entry
        self.description = description
    }
}

public struct LoadedExtension: Sendable {
    public let manifest: ExtensionManifest
    public let directory: URL

    public init(manifest: ExtensionManifest, directory: URL) {
        self.manifest = manifest
        self.directory = directory
    }

    public var scriptURL: URL { directory.appendingPathComponent(manifest.entry) }
}

public enum ExtensionError: Error, Equatable, Sendable {
    case notFound
    case invalidManifest
    case scriptMissing
    case runtimeUnavailable
    case scriptError(String)
    case invalidResult
}

#if canImport(JavaScriptCore)
/// One `JSContext` per extension, confined to a serial queue. The only native
/// capability exposed is `rea.fetch(url, options)`, which returns a promise.
public final class JSEngine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "rea.jsextension")
    private let context: JSContext
    private let session: URLSession
    private let hostAllowList: Set<String>?
    private let timeout: TimeInterval

    public init(
        script: String,
        hostAllowList: Set<String>? = nil,
        timeout: TimeInterval = 20,
        session: URLSession = .shared
    ) throws {
        guard let context = JSContext() else { throw ExtensionError.runtimeUnavailable }
        self.context = context
        self.session = session
        self.hostAllowList = hostAllowList
        self.timeout = timeout
        installBridge()
        context.exceptionHandler = { _, exception in
            NSLog("[Rea extension] \(exception?.toString() ?? "unknown error")")
        }
        context.evaluateScript(script)
        if let exception = context.exception {
            throw ExtensionError.scriptError(exception.toString())
        }
    }

    /// Calls a `rea.source.<fn>` function synchronously on the JS queue and
    /// returns the bridged Swift value.
    public func call(_ function: String, args: [Any] = []) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard let source = self.context.objectForKeyedSubscript("rea")?
                    .objectForKeyedSubscript("source"),
                      let fn = source.objectForKeyedSubscript(function),
                      !fn.isUndefined else {
                    continuation.resume(throwing: ExtensionError.scriptError("missing rea.source.\(function)"))
                    return
                }
                guard let result = fn.call(withArguments: args) else {
                    continuation.resume(throwing: ExtensionError.scriptError("\(function) returned nothing"))
                    return
                }
                if result.isUndefined || result.isNull {
                    continuation.resume(throwing: ExtensionError.invalidResult)
                    return
                }
                // Unwrap promise-like values is left to the script: the contract
                // is synchronous for pages/series and promise-based for fetch.
                continuation.resume(returning: Self.bridge(result))
            }
        }
    }

    private func installBridge() {
        let fetchBlock: @convention(block) (String, JSValue?) -> JSValue = { [weak self] urlString, _ in
            guard let self else { return JSValue(undefinedIn: nil) }
            return self.makeFetchPromise(urlString)
        }
        let rea = JSValue(newObjectIn: context)
        rea?.setObject(fetchBlock, forKeyedSubscript: "fetch" as NSString)
        context.setObject(rea, forKeyedSubscript: "rea" as NSString)
    }

    private func makeFetchPromise(_ urlString: String) -> JSValue {
        let context = self.context
        guard let url = URL(string: urlString) else {
            return JSValue(undefinedIn: context)
        }
        if let hostAllowList, let host = url.host, !hostAllowList.contains(host) {
            return JSValue(undefinedIn: context)
        }

        // The executor runs synchronously, so the resolve/reject pairs have to
        // leave the block with the request task already in flight.
        var resolveRef: JSValue?
        var rejectRef: JSValue?
        let promise = JSValue(
            newPromiseIn: context,
            fromExecutor: { resolve, reject in
                resolveRef = resolve
                rejectRef = reject
            }
        )
        guard let promise, let resolve = resolveRef, let reject = rejectRef else {
            return JSValue(undefinedIn: context)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        session.dataTask(with: request) { data, response, error in
            self.queue.async {
                guard let data,
                      let text = String(data: data, encoding: .utf8) else {
                    let reason = error?.localizedDescription ?? "fetch failed"
                    reject.call(withArguments: [reason])
                    return
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let payload: [String: Any] = ["status": status, "body": text]
                resolve.call(withArguments: [payload])
            }
        }.resume()
        return promise
    }

    /// Converts a `JSValue` into something `Any`-compatible for the Swift side.
    /// `toObject()` is only valid on objects, so primitives go through the
    /// typed accessors instead.
    private static func bridge(_ value: JSValue) -> Any? {
        if value.isString {
            return value.toString()
        }
        if value.isBoolean {
            return value.toBool()
        }
        if value.isNumber {
            let number = value.toDouble()
            return number == number.rounded() ? value.toInt32() : number
        }
        if value.isNull || value.isUndefined {
            return nil
        }
        return value.toObject()
    }
}
#endif
