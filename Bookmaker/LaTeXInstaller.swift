import Foundation

/// Downloads a private copy of TinyTeX (a small TeX Live distribution)
/// into Application Support, so users do not have to install MacTeX
/// themselves. A system-wide TeX installation still takes precedence,
/// see LaTeXEngine.findEngine().
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
				let (archive, response) = try await URLSession.shared.download(from: Self.downloadURL)
				if let http = response as? HTTPURLResponse, http.statusCode != 200 {
					throw NSError(domain: "Bookmaker", code: http.statusCode, userInfo: [
						NSLocalizedDescriptionKey: "Download failed with HTTP \(http.statusCode)."
					])
				}
				await MainActor.run {
					self.statusText = "Unpacking…"
				}
				try Self.unpack(archive: archive)
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

	private static func unpack(archive: URL) throws {
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

		guard let engine = LaTeXEngine.managedEnginePath, fileManager.isExecutableFile(atPath: engine) else {
			throw NSError(domain: "Bookmaker", code: 1, userInfo: [
				NSLocalizedDescriptionKey: "TinyTeX unpacked, but pdflatex was not found inside."
			])
		}
	}
}
