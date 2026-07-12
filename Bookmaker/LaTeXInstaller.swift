import Foundation

/// Downloads a private copy of TinyTeX (a small TeX Live distribution)
/// into Application Support, so users do not have to install MacTeX
/// themselves. A system-wide TeX installation still takes precedence,
/// see LaTeXEngine.findEngine(). Also offers a single-click way to extend
/// an existing TinyTeX install with XeLaTeX/LuaLaTeX support (needed for
/// system/variable fonts) via TinyTeX's own tlmgr, rather than requiring a
/// full separate MacTeX download.
@MainActor
final class LaTeXInstaller: ObservableObject {
	@Published var isInstalling = false
	@Published var statusText = ""
	@Published var errorMessage: String?

	static let downloadURL = URL(string: "https://github.com/rstudio/tinytex-releases/releases/download/daily/TinyTeX-1.tgz")!

	func install(completion: @escaping () -> Void) {
		guard !isInstalling else {
			return
		}
		isInstalling = true
		errorMessage = nil
		statusText = "Downloading TinyTeX (about 120 MB)…"
		Task.detached(priority: .userInitiated) {
			do {
				try await Self.downloadAndUnpackTinyTeX()
				await MainActor.run {
					self.isInstalling = false
					self.statusText = ""
					completion()
				}
			} catch {
				await MainActor.run {
					self.isInstalling = false
					self.statusText = ""
					self.errorMessage = error.localizedDescription
				}
			}
		}
	}

	/// Adds XeLaTeX/LuaLaTeX and common font-related packages to the
	/// app-managed TinyTeX via tlmgr, installing the base TinyTeX first if
	/// it isn't there yet — a single click covers both cases.
	func installXeLaTeXSupport(completion: @escaping () -> Void) {
		guard !isInstalling else {
			return
		}
		isInstalling = true
		errorMessage = nil
		let needsBaseInstall = LaTeXEngine.managedEnginePath(.pdflatex) == nil
		statusText = needsBaseInstall
			? "Downloading TinyTeX (about 120 MB)…"
			: "Adding XeLaTeX support (this can take a few minutes)…"
		Task.detached(priority: .userInitiated) {
			do {
				if needsBaseInstall {
					try await Self.downloadAndUnpackTinyTeX()
					await MainActor.run {
						self.statusText = "Adding XeLaTeX support (this can take a few minutes)…"
					}
				}
				try Self.installTeXLivePackages(["xetex", "luatex", "collection-fontsrecommended", "collection-xetex"])
				await MainActor.run {
					self.isInstalling = false
					self.statusText = ""
					completion()
				}
			} catch {
				await MainActor.run {
					self.isInstalling = false
					self.statusText = ""
					self.errorMessage = error.localizedDescription
				}
			}
		}
	}

	private nonisolated static func downloadAndUnpackTinyTeX() async throws {
		let (archive, response) = try await URLSession.shared.download(from: downloadURL)
		if let http = response as? HTTPURLResponse, http.statusCode != 200 {
			throw NSError(domain: "Bookmaker", code: http.statusCode, userInfo: [
				NSLocalizedDescriptionKey: "Download failed with HTTP \(http.statusCode)."
			])
		}
		try unpack(archive: archive)
	}

	private nonisolated static func unpack(archive: URL) throws {
		let fileManager = FileManager.default
		let root = LaTeXEngine.managedInstallRoot
		try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
		for staleName in [".TinyTeX", "TinyTeX"] {
			try? fileManager.removeItem(at: root.appendingPathComponent(staleName))
		}

		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
		process.arguments = ["-xzf", archive.path, "-C", root.path]
		let errorPipe = Pipe()
		process.standardError = errorPipe
		try process.run()
		let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()
		guard process.terminationStatus == 0 else {
			throw NSError(domain: "Bookmaker", code: Int(process.terminationStatus), userInfo: [
				NSLocalizedDescriptionKey: "Could not unpack TinyTeX: \(String(decoding: errorData, as: UTF8.self))"
			])
		}

		// the archive unpacks as a hidden ".TinyTeX" folder; make it visible
		let hidden = root.appendingPathComponent(".TinyTeX")
		if fileManager.fileExists(atPath: hidden.path) {
			try fileManager.moveItem(at: hidden, to: root.appendingPathComponent("TinyTeX"))
		}

		guard let engine = LaTeXEngine.managedEnginePath(.pdflatex), fileManager.isExecutableFile(atPath: engine) else {
			throw NSError(domain: "Bookmaker", code: 1, userInfo: [
				NSLocalizedDescriptionKey: "TinyTeX unpacked, but pdflatex was not found inside."
			])
		}
	}

	private nonisolated static func installTeXLivePackages(_ packages: [String]) throws {
		guard let tlmgr = LaTeXEngine.managedToolPath("tlmgr") else {
			throw NSError(domain: "Bookmaker", code: 2, userInfo: [
				NSLocalizedDescriptionKey: "Could not find tlmgr inside the installed TinyTeX."
			])
		}
		let process = Process()
		process.executableURL = URL(fileURLWithPath: tlmgr)
		process.arguments = ["install"] + packages
		let outputPipe = Pipe()
		process.standardOutput = outputPipe
		process.standardError = outputPipe
		try process.run()
		let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()
		guard process.terminationStatus == 0 else {
			throw NSError(domain: "Bookmaker", code: Int(process.terminationStatus), userInfo: [
				NSLocalizedDescriptionKey: "Could not install XeLaTeX support: \(String(decoding: outputData, as: UTF8.self))"
			])
		}
	}
}
