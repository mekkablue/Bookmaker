import SwiftUI

/// "Configure Footnotes…" sheet.
struct FootnoteSettingsView: View {
	@Binding var footnotes: FootnoteSettings
	@Environment(\.dismiss) private var dismiss
	@State private var showingFontPicker = false

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

			HStack {
				Text("Font")
					.frame(width: 110, alignment: .leading)
				fontLabel
				Button("Choose System Font…") {
					showingFontPicker = true
				}
				.controlSize(.small)
			}

			Text(footnotes.usesSystemFont
				? "This document uses a system font, so it needs a full TeX install (e.g. MacTeX) with xelatex — the bundled TinyTeX only provides pdflatex."
				: "Footnotes typeset exactly like the book class's own until you change one of these.")
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
		.sheet(isPresented: $showingFontPicker) {
			SystemFontPickerView { chosen in
				footnotes.font = .system(chosen)
			}
		}
	}

	private var fontLabel: some View {
		Group {
			switch footnotes.font {
			case .builtin:
				Picker("", selection: builtinBinding) {
					ForEach(FontChoice.allCases) { choice in
						Text(choice.rawValue).tag(choice)
					}
				}
				.labelsHidden()
				.frame(width: 170)
			case .system(let system):
				Text(system.displayName)
					.lineLimit(1)
					.frame(width: 170, alignment: .leading)
			}
		}
	}

	private var builtinBinding: Binding<FontChoice> {
		Binding(
			get: {
				if case .builtin(let choice) = footnotes.font {
					return choice
				}
				return .computerModern
			},
			set: { footnotes.font = .builtin($0) }
		)
	}
}
