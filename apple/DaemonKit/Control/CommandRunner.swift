#if os(macOS)
import DaemonNativeCore
import Foundation

/// Cómo se autorizó una ejecución. `.automatic` solo ejecuta lo que el núcleo
/// permite sin aprobación; `.userConfirmed` (Neo pulsó un botón o lo pidió
/// explícitamente en el chat) ejecuta también lo que requiere aprobación.
/// Un `deny` del núcleo no se ejecuta nunca.
public enum ExecutionApproval: Sendable { case automatic, userConfirmed }

public struct CommandResult: Sendable {
    public let executable: String
    public let arguments: [String]
    public let exitCode: Int32
    /// Salida cruda: solo para parsear en memoria. Nunca se registra.
    public let standardOutput: String
    public let standardError: String
    public let durationMs: Int
    public let timedOut: Bool
    public let truncated: Bool
    public let decision: PolicyDecision

    public var succeeded: Bool { exitCode == 0 && !timedOut }
    /// Texto apto para mostrar: redactado por el núcleo C++.
    public var displayOutput: String { CoreBridge.redact(String((standardOutput + standardError).suffix(6000))) }
}

public enum CommandError: Error, LocalizedError, Sendable {
    case notInstalled(String)
    case denied(PolicyDecision)
    case needsApproval(PolicyDecision)
    case launchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notInstalled(let name): "\(name) no está instalado (no verificado)."
        case .denied(let decision): "El núcleo deniega este comando: \(decision.reason)."
        case .needsApproval(let decision): "Requiere aprobación de Neo: \(decision.reason)."
        case .launchFailed(let detail): "No se pudo lanzar el proceso: \(detail)."
        }
    }
}

/// Localiza binarios solo en rutas fijas y conocidas; nunca en el PATH heredado.
public enum Toolbox {
    public static let searchDirectories = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
    private static let bundled: [String: String] = [
        "tailscale": "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
    ]

    public static func locate(_ name: String) -> String? {
        if name.hasPrefix("/") { return FileManager.default.isExecutableFile(atPath: name) ? name : nil }
        for directory in searchDirectories {
            let path = directory + "/" + name
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        if let path = bundled[name], FileManager.default.isExecutableFile(atPath: path) { return path }
        return nil
    }
}

public enum CommandRunner {
    public static func policy(_ executable: String, _ arguments: [String], approval: ExecutionApproval) -> PolicyDecision {
        CoreBridge.evaluatePolicy(executable: executable, arguments: arguments,
                                  allowWrite: approval == .userConfirmed, allowNetwork: approval == .userConfirmed)
    }

    /// Ejecuta un binario con argv separado (sin shell), entorno mínimo,
    /// plazo y presupuesto de salida. Pasa siempre por el gate del núcleo.
    public static func run(_ tool: String, _ arguments: [String], in directory: String? = nil,
                           timeout: TimeInterval = 8, maxOutputBytes: Int = 1_048_576,
                           approval: ExecutionApproval = .automatic,
                           extraEnvironment: [String: String] = [:]) async throws -> CommandResult {
        guard let executable = Toolbox.locate(tool) else { throw CommandError.notInstalled(tool) }
        let decision = policy(executable, arguments, approval: approval)
        switch decision.verdict {
        case .deny: throw CommandError.denied(decision)
        case .approval where approval == .automatic: throw CommandError.needsApproval(decision)
        default: break
        }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result {
                    try execute(executable, arguments, directory: directory, timeout: timeout, maxOutputBytes: maxOutputBytes,
                                decision: decision, extraEnvironment: extraEnvironment)
                })
            }
        }
    }

    /// Únicas variables extra aceptadas: selección de SDK y modo CI.
    static let extraEnvironmentKeys: Set<String> = ["SDKROOT", "DAEMON_APPLE_SDK", "CI"]

    static func environment() -> [String: String] {
        let inherited = ProcessInfo.processInfo.environment
        var result: [String: String] = [
            "PATH": Toolbox.searchDirectories.joined(separator: ":"),
            "LANG": inherited["LANG"] ?? "en_US.UTF-8",
            "GIT_TERMINAL_PROMPT": "0", "GIT_OPTIONAL_LOCKS": "0", "GH_PROMPT_DISABLED": "1",
            "NO_COLOR": "1", "GH_NO_UPDATE_NOTIFIER": "1", "PAGER": "cat",
            // La CLI de Tailscale (App Store) solo actúa como CLI si existe TERM.
            "TERM": "dumb",
        ]
        // HOME y USER son necesarios para que gh y ssh encuentren su propia
        // configuración; ninguna variable de credenciales se reenvía.
        for key in ["HOME", "USER", "TMPDIR", "SSH_AUTH_SOCK"] { if let value = inherited[key] { result[key] = value } }
        return result
    }

    private static func execute(_ executable: String, _ arguments: [String], directory: String?, timeout: TimeInterval,
                                maxOutputBytes: Int, decision: PolicyDecision, extraEnvironment: [String: String]) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var childEnvironment = CommandRunner.environment()
        for (key, value) in extraEnvironment where extraEnvironmentKeys.contains(key) { childEnvironment[key] = value }
        process.environment = childEnvironment
        process.standardInput = FileHandle.nullDevice
        if let directory { process.currentDirectoryURL = URL(fileURLWithPath: directory, isDirectory: true) }
        let output = Pipe(), error = Pipe()
        process.standardOutput = output
        process.standardError = error
        let buffer = OutputBuffer(limit: maxOutputBytes)
        output.fileHandleForReading.readabilityHandler = { handle in buffer.append(handle.availableData, error: false) }
        error.fileHandleForReading.readabilityHandler = { handle in buffer.append(handle.availableData, error: true) }
        let started = Date()
        do { try process.run() } catch { throw CommandError.launchFailed(error.localizedDescription) }
        let deadline = started.addingTimeInterval(timeout)
        var timedOut = false
        while process.isRunning {
            if Date() >= deadline || buffer.exceeded { timedOut = Date() >= deadline; process.terminate(); break }
            Thread.sleep(forTimeInterval: 0.01)
        }
        if process.isRunning {
            Thread.sleep(forTimeInterval: 0.2)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
        output.fileHandleForReading.readabilityHandler = nil
        error.fileHandleForReading.readabilityHandler = nil
        buffer.append(output.fileHandleForReading.readDataToEndOfFile(), error: false)
        buffer.append(error.fileHandleForReading.readDataToEndOfFile(), error: true)
        let snapshot = buffer.snapshot()
        return CommandResult(executable: executable, arguments: arguments, exitCode: process.terminationStatus,
                             standardOutput: snapshot.out, standardError: snapshot.err,
                             durationMs: Int(Date().timeIntervalSince(started) * 1000), timedOut: timedOut,
                             truncated: snapshot.truncated, decision: decision)
    }
}

/// Buffer acotado y seguro entre hilos para stdout/stderr.
final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var out = Data(), err = Data()
    private let limit: Int
    private var overflow = false
    var exceeded: Bool { lock.lock(); defer { lock.unlock() }; return overflow }

    init(limit: Int) { self.limit = limit }

    func append(_ data: Data, error: Bool) {
        guard !data.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        let room = max(0, limit - out.count - err.count)
        if data.count > room { overflow = true }
        let accepted = data.prefix(room)
        if error { err.append(accepted) } else { out.append(accepted) }
    }

    func snapshot() -> (out: String, err: String, truncated: Bool) {
        lock.lock(); defer { lock.unlock() }
        return (String(decoding: out, as: UTF8.self), String(decoding: err, as: UTF8.self), overflow)
    }
}
#endif
