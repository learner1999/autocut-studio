import Foundation

enum BackendError: LocalizedError {
    case processFailed(String)
    case missingRepositoryRoot

    var errorDescription: String? {
        switch self {
        case .processFailed(let message):
            return message
        case .missingRepositoryRoot:
            return "Could not locate the AutoCut repository root."
        }
    }
}

final class PythonBackend {
    typealias ProgressHandler = (BackendProgress) -> Void

    private let repositoryRoot: URL
    private let python: URL
    private static let repositoryRootEnvironmentKey = "AUTOCUT_REPO_ROOT"
    private static let progressPrefix = "AUTOCUT_PROGRESS "

    init(repositoryRoot: URL = PythonBackend.defaultRepositoryRoot()) {
        self.repositoryRoot = repositoryRoot
        self.python = repositoryRoot.appendingPathComponent(".venv/bin/python")
    }

    func probe(mediaURL: URL) async throws -> ProbeResult {
        try await run(["probe", "--media", mediaURL.path], as: ProbeResult.self)
    }

    func waveform(mediaURL: URL, samples: Int = 2400) async throws -> [Double] {
        let response = try await run(
            ["waveform", "--media", mediaURL.path, "--samples", "\(samples)"],
            as: WaveformResult.self
        )
        return response.samples
    }

    func transcribe(
        mediaURL: URL,
        settings: ProjectSettings,
        onProgress: ProgressHandler? = nil
    ) async throws -> AutoCutProject {
        try await run(
            [
                "transcribe",
                "--media", mediaURL.path,
                "--lang", settings.lang,
                "--model", settings.whisperModel,
                "--vad", "0",
                "--pad-head", "\(settings.padHead)",
                "--pad-tail", "\(settings.padTail)",
                "--merge-gap", "\(settings.mergeGap)",
                "--bitrate", settings.bitrate,
                "--progress",
            ],
            as: AutoCutProject.self,
            onProgress: onProgress
        )
    }

    func projectFromSRT(mediaURL: URL, srtURL: URL, mdURL: URL?) async throws -> AutoCutProject {
        var arguments = [
            "project-from-srt",
            "--media", mediaURL.path,
            "--srt", srtURL.path,
        ]
        if let mdURL {
            arguments += ["--md", mdURL.path]
        }
        return try await run(arguments, as: AutoCutProject.self)
    }

    func retranscribe(
        mediaURL: URL,
        segment: ProjectSegment,
        settings: ProjectSettings,
        onProgress: ProgressHandler? = nil
    ) async throws -> RetranscribeResult {
        try await run(
            [
                "retranscribe-range",
                "--media", mediaURL.path,
                "--start", "\(segment.start)",
                "--end", "\(segment.end)",
                "--lang", settings.lang,
                "--model", settings.whisperModel,
                "--progress",
            ],
            as: RetranscribeResult.self,
            onProgress: onProgress
        )
    }

    func export(projectURL: URL, outputURL: URL) async throws -> ExportResult {
        try await run(
            ["export", "--project", projectURL.path, "--output", outputURL.path],
            as: ExportResult.self
        )
    }

    func exportSRT(projectURL: URL, outputURL: URL) async throws -> ExportResult {
        try await run(
            ["export-srt", "--project", projectURL.path, "--output", outputURL.path],
            as: ExportResult.self
        )
    }

    func exportMD(projectURL: URL, outputURL: URL) async throws -> ExportResult {
        try await run(
            ["export-md", "--project", projectURL.path, "--output", outputURL.path],
            as: ExportResult.self
        )
    }

    private func run<T: Decodable>(
        _ arguments: [String],
        as type: T.Type,
        onProgress: ProgressHandler? = nil
    ) async throws -> T {
        let python = self.python
        let repositoryRoot = self.repositoryRoot
        return try await Task.detached(priority: .userInitiated) {
            guard FileManager.default.fileExists(atPath: python.path) else {
                throw BackendError.processFailed("Python backend executable was not found at \(python.path).")
            }

            let process = Process()
            process.executableURL = python
            process.arguments = ["-m", "autocut.app_backend"] + arguments
            process.currentDirectoryURL = repositoryRoot

            process.environment = Self.backendEnvironment(repositoryRoot: repositoryRoot)

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            let bufferQueue = DispatchQueue(label: "studio.autocut.python-backend.buffers")
            var stdoutData = Data()
            var stderrLineBuffer = ""
            var stderrDiagnostics = ""

            stdout.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                bufferQueue.async {
                    stdoutData.append(data)
                }
            }

            stderr.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                bufferQueue.async {
                    Self.consumeStderr(
                        data,
                        lineBuffer: &stderrLineBuffer,
                        diagnostics: &stderrDiagnostics,
                        onProgress: onProgress
                    )
                }
            }

            do {
                try process.run()
            } catch {
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                throw BackendError.processFailed("Could not start Python backend at \(python.path): \(error.localizedDescription)")
            }
            process.waitUntilExit()

            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil

            let remainingOutput = stdout.fileHandleForReading.readDataToEndOfFile()
            let remainingError = stderr.fileHandleForReading.readDataToEndOfFile()
            bufferQueue.sync {
                stdoutData.append(remainingOutput)
                Self.consumeStderr(
                    remainingError,
                    lineBuffer: &stderrLineBuffer,
                    diagnostics: &stderrDiagnostics,
                    onProgress: onProgress
                )
                Self.flushStderrLineBuffer(
                    &stderrLineBuffer,
                    diagnostics: &stderrDiagnostics,
                    onProgress: onProgress
                )
            }

            if process.terminationStatus != 0 {
                let message = stderrDiagnostics.isEmpty ? "Python backend failed." : stderrDiagnostics
                throw BackendError.processFailed(message)
            }
            do {
                return try JSONDecoder().decode(T.self, from: stdoutData)
            } catch {
                let raw = String(data: stdoutData, encoding: .utf8) ?? ""
                throw BackendError.processFailed("Could not decode backend response: \(error)\n\(raw)\n\(stderrDiagnostics)")
            }
        }.value
    }

    static func progressEvent(fromStderrLine line: String) -> BackendProgress? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(progressPrefix) else { return nil }
        let payload = trimmed.dropFirst(progressPrefix.count)
        return try? JSONDecoder().decode(BackendProgress.self, from: Data(payload.utf8))
    }

    private static func consumeStderr(
        _ data: Data,
        lineBuffer: inout String,
        diagnostics: inout String,
        onProgress: ProgressHandler?
    ) {
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
        lineBuffer.append(text)
        while let newline = lineBuffer.firstIndex(of: "\n") {
            let line = String(lineBuffer[..<newline])
            lineBuffer.removeSubrange(...newline)
            consumeStderrLine(line, diagnostics: &diagnostics, onProgress: onProgress)
        }
    }

    private static func flushStderrLineBuffer(
        _ lineBuffer: inout String,
        diagnostics: inout String,
        onProgress: ProgressHandler?
    ) {
        guard !lineBuffer.isEmpty else { return }
        consumeStderrLine(lineBuffer, diagnostics: &diagnostics, onProgress: onProgress)
        lineBuffer = ""
    }

    private static func consumeStderrLine(
        _ line: String,
        diagnostics: inout String,
        onProgress: ProgressHandler?
    ) {
        if let progress = progressEvent(fromStderrLine: line) {
            onProgress?(progress)
        } else if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            diagnostics += line + "\n"
        }
    }

    private static func defaultRepositoryRoot() -> URL {
        repositoryRoot(
            environment: ProcessInfo.processInfo.environment,
            bundleRepositoryRoot: Bundle.main.object(forInfoDictionaryKey: "AutoCutRepoRoot") as? String,
            executableURL: Bundle.main.executableURL,
            currentDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        )
    }

    static func repositoryRoot(
        environment: [String: String],
        bundleRepositoryRoot: String? = nil,
        executableURL: URL?,
        currentDirectory: URL,
        fileManager: FileManager = .default
    ) -> URL {
        if let path = environment[repositoryRootEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty {
            return URL(fileURLWithPath: path)
        }

        if let path = bundleRepositoryRoot?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty {
            return URL(fileURLWithPath: path)
        }

        let searchRoots = [
            executableURL?.deletingLastPathComponent(),
            currentDirectory,
        ].compactMap { $0 }

        if let root = firstExistingRepositoryRoot(startingAt: searchRoots, fileManager: fileManager) {
            return root
        }

        return executableURLFallback(executableURL: executableURL) ?? currentDirectory
    }

    private static func firstExistingRepositoryRoot(
        startingAt candidates: [URL],
        fileManager: FileManager
    ) -> URL? {
        for candidate in candidates {
            var directory = candidate
            for _ in 0..<12 {
                if isRepositoryRoot(directory, fileManager: fileManager) {
                    return directory
                }

                let parent = directory.deletingLastPathComponent()
                if parent.path == directory.path {
                    break
                }
                directory = parent
            }
        }

        return nil
    }

    private static func isRepositoryRoot(_ url: URL, fileManager: FileManager) -> Bool {
        fileManager.fileExists(atPath: url.appendingPathComponent(".venv/bin/python").path)
            && fileManager.fileExists(atPath: url.appendingPathComponent("autocut/app_backend.py").path)
    }

    private static func executableURLFallback(executableURL: URL?) -> URL? {
        executableURL?
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static func backendEnvironment(
        repositoryRoot: URL,
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment = base
        environment["PYTHONPATH"] = repositoryRoot.path

        let requiredToolPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
        let existingPaths = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        var mergedPaths: [String] = []
        for path in requiredToolPaths + existingPaths where !mergedPaths.contains(path) {
            mergedPaths.append(path)
        }
        environment["PATH"] = mergedPaths.joined(separator: ":")
        return environment
    }
}
