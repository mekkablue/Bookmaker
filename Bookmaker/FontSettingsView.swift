import SwiftUI

/// "Edit Fonts…" sheet: pick a default font for each text role. Only fonts
/// that plain pdflatex can already set are offered, so every combination
/// typesets without extra font installation.
struct FontSettingsView: View {
	@Binding var fonts: FontSettings
	@Environment(\.dismiss) private var dismiss

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			Text("Edit Fonts")
				.font(.title2.bold())

			VStack(alignment: .leading, spacing: 12) {
				fontRow("Body Text", "Paragraph text throughout the book.", $fonts.bodyFont)
				fontRow("Headings", "Chapter and section titles.", $fonts.headingFont)
				fontRow("Captions", "Available in body text as \\captionfont, e.g. {\\captionfont Some text}.", $fonts.captionFont)
			}

			Text("These are built-in pdflatex fonts, so every choice typesets without installing anything extra.")
				.font(.caption)
				.foregroundColor(.secondary)

			HStack {
				Spacer()
				Button("Done") {
					dismiss()
				}
				.keyboardShortcut(.defaultAction)
			}
		}
		.padding(20)
		.frame(width: 420)
	}

	private func fontRow(_ title: String, _ hint: String, _ selection: Binding<FontChoice>) -> some View {
		VStack(alignment: .leading, spacing: 2) {
			HStack {
				Text(title)
					.frame(width: 90, alignment: .leading)
				Picker("", selection: selection) {
					ForEach(FontChoice.allCases) { choice in
						Text(choice.rawValue).tag(choice)
					}
				}
				.labelsHidden()
			}
			Text(hint)
				.font(.caption)
				.foregroundColor(.secondary)
				.padding(.leading, 90)
		}
	}
}
