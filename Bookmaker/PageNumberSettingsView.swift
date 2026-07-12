import SwiftUI

/// Page number controls for the GUI canvas: enable/disable and a position
/// grid defined in terms of the page margins, so numbers stay aligned as
/// margins change. Font, size, and color are set in "Edit Styles…".
struct PageNumberSettingsView: View {
	@Binding var pageNumbers: PageNumberSettings

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

				Text("Font, size, and color are set in Edit ▸ Edit Styles…")
					.font(.caption)
					.foregroundColor(.secondary)
			}
		}
		.padding(16)
		.frame(width: 320)
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
