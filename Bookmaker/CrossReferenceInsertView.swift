import SwiftUI

/// Lists existing `\label{}` marks found in the body text so the user can
/// insert a cross-reference to one, phrased automatically ("above"/"below"/
/// "on page N") once the book is typeset.
struct CrossReferenceInsertView: View {
	let bodyText: String
	let introWord: String
	var onSelect: (String) -> Void
	@Environment(\.dismiss) private var dismiss

	private var labels: [String] {
		LabelScanner.labels(in: bodyText).sorted()
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text("Insert Cross-Reference")
				.font(.title3.bold())

			if labels.isEmpty {
				Text("No reference marks yet. Use “Insert Reference Mark” at the spot you want to point to, then come back here.")
					.font(.caption)
					.foregroundColor(.secondary)
					.frame(width: 300)
			} else {
				Text("Choose a mark. Bookmaker inserts “\(introWord) …” with the position filled in automatically once typeset.")
					.font(.caption)
					.foregroundColor(.secondary)
					.frame(width: 300)
				List(labels, id: \.self) { label in
					Button {
						onSelect(label)
						dismiss()
					} label: {
						Text(label)
							.frame(maxWidth: .infinity, alignment: .leading)
					}
					.buttonStyle(.plain)
				}
				.frame(height: 160)
			}

			HStack {
				Spacer()
				Button("Cancel") {
					dismiss()
				}
			}
		}
		.padding(16)
		.frame(width: 340)
	}
}
