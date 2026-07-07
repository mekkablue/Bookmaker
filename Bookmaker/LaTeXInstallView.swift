import SwiftUI

/// Shown in the preview pane when no pdflatex is found on the system.
struct LaTeXInstallView: View {
	@ObservedObject var installer: LaTeXInstaller
	var onInstalled: () -> Void

	var body: some View {
		VStack(spacing: 12) {
			Image(systemName: "text.book.closed")
				.font(.system(size: 36))
				.foregroundColor(.secondary)
			Text("No LaTeX Found")
				.font(.headline)
			Text("Bookmaker typesets with pdflatex. Install a private copy of TinyTeX into Application Support — about 120 MB, no admin password needed — or install a full MacTeX yourself.")
				.font(.caption)
				.foregroundColor(.secondary)
				.multilineTextAlignment(.center)
				.frame(maxWidth: 340)
			if installer.isInstalling {
				ProgressView(installer.statusText)
			} else {
				Button("Install LaTeX") {
					installer.install(completion: onInstalled)
				}
				.keyboardShortcut(.defaultAction)
				Link("Get MacTeX instead…", destination: URL(string: "https://tug.org/mactex/")!)
					.font(.caption)
			}
			if let error = installer.errorMessage {
				Text(error)
					.font(.caption)
					.foregroundColor(.red)
					.multilineTextAlignment(.center)
					.frame(maxWidth: 340)
			}
		}
		.padding(20)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}
}
