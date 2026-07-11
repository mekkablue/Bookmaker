import SwiftUI

/// Page number controls for the GUI canvas: enable/disable, font, size, and
/// a position grid defined in terms of the page margins, so numbers stay
/// aligned as margins change.
struct PageNumberSettingsView: View {
	@Binding var pageNumbers: PageNumberSettings
	@State private var showingFontPicker = false

	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			Toggle("Show Page Numbers", isOn: $pageNumbers.isEnabled)
				.font(.headline)

			if pageNumbers.isEnabled {
				Divider()

				VStack(alignment: .leading, spacing: 6) {
					Text("Position")
						.font(.caption)
						.foregroundColor(.secondary)
					positionGrid
				}

				HStack {
					Text("Inset from margin")
						.frame(width: 130, alignment: .leading)
					TextField("", value: $pageNumbers.marginInset, format: .number)
						.textFieldStyle(.roundedBorder)
						.frame(width: 52)
					Text("mm")
						.font(.caption)
						.foregroundColor(.secondary)
				}

				HStack {
					Text("Font")
						.frame(width: 130, alignment: .leading)
					fontLabel
					Button("Choose…") {
						showingFontPicker = true
					}
					.controlSize(.small)
				}

				HStack {
					Text("Size")
						.frame(width: 130, alignment: .leading)
					TextField("", value: $pageNumbers.fontSize, format: .number)
						.textFieldStyle(.roundedBorder)
						.frame(width: 52)
					Text("pt")
						.font(.caption)
						.foregroundColor(.secondary)
				}

				if pageNumbers.usesSystemFont {
					Text("Needs a full TeX install (e.g. MacTeX) with xelatex.")
						.font(.caption)
						.foregroundColor(.secondary)
				}
			}
		}
		.padding(16)
		.frame(width: 320)
		.sheet(isPresented: $showingFontPicker) {
			SystemFontPickerView { chosen in
				pageNumbers.font = .system(chosen)
			}
		}
	}

	private var fontLabel: some View {
		Group {
			switch pageNumbers.font {
			case .builtin:
				Picker("", selection: builtinBinding) {
					ForEach(FontChoice.allCases) { choice in
						Text(choice.rawValue).tag(choice)
					}
				}
				.labelsHidden()
				.frame(width: 130)
			case .system(let system):
				Text(system.displayName)
					.lineLimit(1)
					.frame(width: 130, alignment: .leading)
			}
		}
	}

	private var builtinBinding: Binding<FontChoice> {
		Binding(
			get: {
				if case .builtin(let choice) = pageNumbers.font {
					return choice
				}
				return .computerModern
			},
			set: { pageNumbers.font = .builtin($0) }
		)
	}

	private var positionGrid: some View {
		VStack(spacing: 4) {
			ForEach(PageNumberVerticalPosition.allCases) { vertical in
				HStack(spacing: 4) {
					ForEach(PageNumberHorizontalPosition.allCases) { horizontal in
						positionButton(vertical, horizontal)
					}
				}
			}
		}
	}

	private func positionButton(_ vertical: PageNumberVerticalPosition, _ horizontal: PageNumberHorizontalPosition) -> some View {
		let isSelected = pageNumbers.vertical == vertical && pageNumbers.horizontal == horizontal
		return Button {
			pageNumbers.vertical = vertical
			pageNumbers.horizontal = horizontal
		} label: {
			Text("\(vertical.rawValue) \(horizontal.rawValue)")
				.font(.caption)
				.frame(maxWidth: .infinity)
				.padding(.vertical, 6)
				.background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
				.foregroundColor(isSelected ? .white : .primary)
				.cornerRadius(4)
		}
		.buttonStyle(.plain)
	}
}
