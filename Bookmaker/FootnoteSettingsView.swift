import SwiftUI

/// "Configure Footnotes…" sheet.
struct FootnoteSettingsView: View {
	@Binding var footnotes: FootnoteSettings
	@Environment(\.dismiss) private var dismiss

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			Text("Configure Footnotes")
				.font(.title2.bold())

			HStack {
				Text("Numbering")
					.frame(width: 110, alignment: .leading)
				Picker("", selection: $footnotes.numberingStyle) {
					ForEach(FootnoteNumberingStyle.allCases) { style in
						Text(style.rawValue).tag(style)
					}
				}
				.labelsHidden()
				.frame(width: 140)
			}

			Toggle(isOn: $footnotes.resetsPerPage) {
				Text("Restart numbering on every page")
			}

			Text("Font, size, and color are set in Edit ▸ Edit Styles…")
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
}
