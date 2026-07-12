import Foundation

struct TypesetResult {
	var pdfData: Data?
	var log: String
	var errorMessage: String?
	var engineMissing = false
}

/// Which TeX binary compiles the document. pdflatex handles everything the
/// app could produce until a document uses a system/variable font or custom
/// page numbers, at which point it needs XeLaTeX's fontspec support instead.
enum LaTeXEngineKind: String {
	case pdflatex
	case xelatex
	case lualatex
}

enum LaTeXEngine {
	private static let searchRoots = [
		"/Library/TeX/texbin",
		"/opt/homebrew/bin",
		"/usr/local/bin",
		"/usr/texbin",
	]

	/// Root folder for the app-managed TinyTeX installation (~/Library/Application Support/Bookmaker).
	static var managedInstallRoot: URL {
		let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
			?? FileManager.default.temporaryDirectory
		return appSupport.appendingPathComponent("Bookmaker", isDirectory: true)
	}

	/// The named binary inside the app-managed TinyTeX, if installed (platform
	/// folder varies, e.g. universal-darwin). Works for engines (pdflatex,
	/// xelatex, ...) and TinyTeX's own tools (tlmgr).
	static func managedToolPath(_ toolName: String) -> String? {
		let binRoot = managedInstallRoot.appendingPathComponent("TinyTeX/bin", isDirectory: true)
		guard let platforms = try? FileManager.default.contentsOfDirectory(atPath: binRoot.path) else {
			return nil
		}
		for platform in platforms {
			let candidate = binRoot.appendingPathComponent(platform).appendingPathComponent(toolName).path
			if FileManager.default.isExecutableFile(atPath: candidate) {
				return candidate
			}
		}
		return nil
	}

	/// TinyTeX's smallest bundle only provides pdflatex, so this is usually nil for xelatex/lualatex
	/// until LaTeXInstaller.installXeLaTeXSupport() adds them via tlmgr.
	static func managedEnginePath(_ kind: LaTeXEngineKind) -> String? {
		managedToolPath(kind.rawValue)
	}

	static func findEngine(_ kind: LaTeXEngineKind) -> String? {
		for root in searchRoots {
			let path = "\(root)/\(kind.rawValue)"
			if FileManager.default.isExecutableFile(atPath: path) {
				return path
			}
		}
		if let managed = managedEnginePath(kind) {
			return managed
		}
		// last resort: the user's login shell may know a PATH that the app does not
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/bin/zsh")
		process.arguments = ["-l", "-c", "command -v \(kind.rawValue)"]
		let pipe = Pipe()
		process.standardOutput = pipe
		process.standardError = Pipe()
		do {
			try process.run()
			let data = pipe.fileHandleForReading.readDataToEndOfFile()
			process.waitUntilExit()
			if process.terminationStatus == 0 {
				let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
				if !path.isEmpty {
					return path
				}
			}
		} catch {
			// fall through
		}
		return nil
	}

	static func typeset(source: String, in directory: URL, engine kind: LaTeXEngineKind = .pdflatex) -> TypesetResult {
		guard let engine = findEngine(kind) else {
			var message = "No \(kind.rawValue) found."
			if kind != .pdflatex {
				message += " This document uses a system or variable font, which needs a full TeX install (e.g. MacTeX) with \(kind.rawValue) — the bundled TinyTeX only provides pdflatex."
			}
			return TypesetResult(pdfData: nil, log: "", errorMessage: message, engineMissing: true)
		}
		let pdfURL = directory.appendingPathComponent("main.pdf")
		do {
			try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
			try source.write(to: directory.appendingPathComponent("main.tex"), atomically: true, encoding: .utf8)

			var lastLog = ""
			// two passes so the table of contents and page references settle
			for _ in 0 ..< 2 {
				let (status, output) = runEngine(engine, in: directory)
				lastLog = output
				if status != 0 {
					return TypesetResult(
						pdfData: try? Data(contentsOf: pdfURL),
						log: output,
						errorMessage: firstErrorLine(in: output) ?? "\(kind.rawValue) exited with status \(status)."
					)
				}
			}
			return TypesetResult(pdfData: try Data(contentsOf: pdfURL), log: lastLog, errorMessage: nil)
		} catch {
			return TypesetResult(pdfData: nil, log: "", errorMessage: error.localizedDescription)
		}
	}

	private static func runEngine(_ engine: String, in directory: URL) -> (Int32, String) {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: engine)
		process.arguments = ["-interaction=nonstopmode", "-file-line-error", "main.tex"]
		process.currentDirectoryURL = directory
		let pipe = Pipe()
		process.standardOutput = pipe
		process.standardError = pipe
		do {
			try process.run()
		} catch {
			return (-1, "Could not launch \(engine): \(error.localizedDescription)")
		}
		let data = pipe.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()
		return (process.terminationStatus, String(decoding: data, as: UTF8.self))
	}

	private static func firstErrorLine(in log: String) -> String? {
		for line in log.split(separator: "\n") {
			if line.hasPrefix("!") || line.range(of: #"^[^:]+\.tex:\d+:"#, options: .regularExpression) != nil {
				return String(line)
			}
		}
		return nil
	}
}
