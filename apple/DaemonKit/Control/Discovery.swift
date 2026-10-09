import Foundation

/// Descubre repositorios Git dentro del workspace de Scenarys. Excluye copias
/// de seguridad, clones fallidos, dependencias y builds.
public enum RepositoryDiscovery {
    static let skipped: Set<String> = ["node_modules", ".build", "build", "dist", ".git", ".expo", "DerivedData", "Pods", ".logs", ".pendientes", ".daemon-runner"]
    static let excludedMarkers = ["backup", "clon-fallido", "esqueleto", ".old", "-copy"]

    public struct Found: Sendable, Hashable, Identifiable {
        public let path: String
        public let name: String
        public let worktree: Bool
        public var id: String { path }
    }

    public static func discover(root: String, maxDepth: Int = 3) -> [Found] {
        let manager = FileManager.default
        var found: [Found] = []
        func walk(_ url: URL, depth: Int) {
            guard depth <= maxDepth else { return }
            let gitPath = url.appendingPathComponent(".git").path
            var isDirectory: ObjCBool = false
            if manager.fileExists(atPath: gitPath, isDirectory: &isDirectory) {
                let name = url.lastPathComponent == "repo" ? url.deletingLastPathComponent().lastPathComponent : url.lastPathComponent
                found.append(Found(path: url.path, name: name, worktree: !isDirectory.boolValue))
                if isDirectory.boolValue { return }
            }
            guard let children = try? manager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }
            for child in children {
                let name = child.lastPathComponent
                guard !skipped.contains(name), !excludedMarkers.contains(where: { name.lowercased().contains($0) }),
                      (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                walk(child, depth: depth + 1)
            }
        }
        walk(URL(fileURLWithPath: (root as NSString).expandingTildeInPath, isDirectory: true), depth: 0)
        return found.sorted { ($0.worktree ? 1 : 0, $0.name) < ($1.worktree ? 1 : 0, $1.name) }
    }
}
