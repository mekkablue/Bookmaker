import SwiftUI

/// "Edit Fonts…" sheet: pick a default font for each text role, either from
/// the curated pdflatex-safe list or any font installed on the system
/// (which may be a variable font, offering axis sliders instead of a flat
/// style list).
struct FontSettingsView: View {
	@Binding var fonts: FontSettings
	@Environment(\.dismiss) private var dismiss

	private enum Role: String, Identifiable {
		case body = "Body Text"
		case heading = "Headings"
		case caption = "Captions"
		var id: String { rawValue }
	}

	@State private var presentingRole: Role?

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			Text("Edit Fonts")
				.font(.title2.bold())

			VStack(alignment: .leading, spacing: 14) {
				fontRow(.body, "Paragraph text throughout the book.", $fonts.bodyFont)
				fontRow(.heading, "Chapter and section titles.", $fonts.headingFont)
				fontRow(.caption, "Available in body text as \\captionfont, e.g. {\\captionfont Some text}.", $fonts.captionFont)
			}

			Text(fonts.usesSystemFont
				? "This document uses a system font, so it needs a full TeX install (e.g. MacTeX) with xelatex — the bundled TinyTeX only provides pdflatex."
				: "These are built-in pdflatex fonts, so every choice typesets without installing anything extra.")
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
		.frame(width: 460)
	}

	private func fontRow(_ role: Role, _ hint: String, _ selection: Binding<FontSelection>) -> some View {
		VStack(alignment: .leading, spacing: 2) {
			HStack {
				Text(role.rawValue)
					.frame(width: 90, alignment: .leading)
				switch selection.wrappedValue {
				case .builtin:
					Picker("", selection: builtinBinding(selection)) {
						ForEach(FontChoice.allCases) { choice in
							Text(choice.rawValue).tag(choice)
						}
					}
					.labelsHidden()
					.frame(width: 200)
				case .system(let system):
					Text(system.familyName + (system.familyName == system.displayName ? "" : " \(system.displayName)"))
						.lineLimit(1)
						.frame(width: 200, alignment: .leading)
				}
				Button("Choose System Font…") {
					presentingRole = role
				}
				.controlSize(.small)
			}
			Text(hint)
				.font(.caption)
				.foregroundColor(.secondary)
				.padding(.leading, 90)
		}
		.sheet(isPresented: Binding(
			get: { presentingRole == role },
			set: { isPresented in if !isPresented { presentingRole = nil } }
		)) {
			SystemFontPickerView { chosen in
				selection.wrappedValue = .system(chosen)
			}
		}
	}

	private func builtinBinding(_ selection: Binding<FontSelection>) -> Binding<FontChoice> {
		Binding(
			get: {
				if case .builtin(let choice) = selection.wrappedValue {
					return choice
				}
				return .computerModern
			},
			set: { selection.wrappedValue = .builtin($0) }
		)
	}
}
