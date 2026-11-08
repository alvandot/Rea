import Foundation

/// Scans a directory of `manifest.json` + script bundles and builds JS sources.
public struct JavaScriptCoreExtensionRuntime: Sendable {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func availableManifests() async throws -> [LoadedExtension] {
        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return []
        }

        var loaded: [LoadedExtension] = []
        for url in contents {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDirectory else { continue }
            let manifestURL = url.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? JSONDecoder().decode(ExtensionManifest.self, from: data) else {
                continue
            }
            loaded.append(LoadedExtension(manifest: manifest, directory: url))
        }
        return loaded
    }

    public func makeSource(from loaded: LoadedExtension) async throws -> (any ContentSource)? {
        #if canImport(JavaScriptCore)
        guard let script = try? String(contentsOf: loaded.scriptURL, encoding: .utf8) else {
            throw ExtensionError.scriptMissing
        }
        let engine = try JSEngine(script: script)
        return JSContentSource(manifest: loaded.manifest, engine: engine)
        #else
        return nil
        #endif
    }
}
