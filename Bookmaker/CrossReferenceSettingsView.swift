import SwiftUI

/// "Configure Cross-References…" sheet.
struct CrossReferenceSettingsView: View {
	@Binding var crossReferences: CrossReferenceSettings
	@Environment(\.dismiss) private var dismiss

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			Text("Configure Cross-References")
				.font(.title2.bold())

			HStack {
				Text("Intro word")
					.frame(width: 110, alignment: .leading)
				TextField("see", text: $crossReferences.introWord)
					.textFieldStyle(.roundedBorder)
					.frame(width: 140)
			}

			Toggle(isOn: $crossReferences.useAboveBelowPhrasing) {
				Text("Say “above”/“below” for marks on a nearby page")
			}

			Text("A reference to a mark far from the current spot always shows its page number, e.g. “\(crossReferences.introWord) page 12”. A nearby mark instead says “\(crossReferences.introWord) \(crossReferences.useAboveBelowPhrasing ? "above" : "on the preceding page")”. This is decided automatically each time the book is typeset.")
				.font(.caption)
				.foregroundColor(.secondary)
				.frame(maxWidth: 380)

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
