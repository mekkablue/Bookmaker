import SwiftUI

/// "Table of Contents…" sheet: choose which heading levels to include, a
/// custom LaTeX line template with <TEXT>/<PAGE> placeholders per level, and
/// any search & replace cleanup for the extracted heading text. Reads real
/// headings and page numbers from the most recent successful typeset.
struct TOCBuilderView: View {
	@Binding var settings: TOCSettings
	let entries: [TOCEntry]
	var onInsert: (String) -> Void
	@Environment(\.dismiss) private var dismiss

	@State private var expandedLevels: Set<String> = ["chapter"]

	private var generated: String {
		settings.generate(from: entries)
	}

	private var levelsPresent: Set<String> {
		Set(entries.map(\.level))
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text("Table of Contents")
				.font(.title2.bold())

			if entries.isEmpty {
				Text("Typeset the book once to detect headings and their page numbers.")
					.font(.caption)
					.foregroundColor(.secondary)
			} else {
				Text("Found \(entries.count) heading\(entries.count == 1 ? "" : "s") in the last typeset. Click Insert again any time after retypesetting to refresh page numbers.")
					.font(.caption)
					.foregroundColor(.secondary)
			}

			ScrollView {
				VStack(alignment: .leading, spacing: 10) {
					ForEach(settings.levels.indices, id: \.self) { index in
						levelRow(index)
					}
				}
			}
			.frame(height: 260)

			VStack(alignment: .leading, spacing: 4) {
				Text("Preview")
					.font(.caption)
					.foregroundColor(.secondary)
				ScrollView {
					Text(generated.isEmpty ? "Nothing to show yet." : generated)
						.font(.system(size: 11, design: .monospaced))
						.frame(maxWidth: .infinity, alignment: .leading)
						.textSelection(.enabled)
						.padding(6)
				}
				.frame(height: 90)
				.background(Color(nsColor: .textBackgroundColor))
				.cornerRadius(4)
			}

			HStack {
				Spacer()
				Button("Done") {
					dismiss()
				}
				Button("Insert into TOC Template") {
					onInsert(generated)
					dismiss()
				}
				.keyboardShortcut(.defaultAction)
				.disabled(generated.isEmpty)
			}
		}
		.padding(20)
		.frame(width: 520)
	}

	private func levelRow(_ index: Int) -> some View {
		let level = settings.levels[index].level
		return DisclosureGroup(isExpanded: Binding(
			get: { expandedLevels.contains(level) },
			set: { isExpanded in
				if isExpanded {
					expandedLevels.insert(level)
				} else {
					expandedLevels.remove(level)
				}
			}
		)) {
			VStack(alignment: .leading, spacing: 8) {
				HStack {
					Text("Line")
						.font(.caption)
						.foregroundColor(.secondary)
						.frame(width: 50, alignment: .leading)
					TextField(#"\t<TEXT>\t<PAGE>"#, text: $settings.levels[index].lineTemplate)
						.textFieldStyle(.roundedBorder)
						.font(.system(size: 11, design: .monospaced))
				}
				transformRulesEditor(index)
			}
			.padding(.top, 4)
			.padding(.leading, 4)
		} label: {
			HStack {
				Toggle(isOn: $settings.levels[index].isIncluded) {
					Text(settings.levels[index].displayName)
				}
				if !levelsPresent.contains(level) {
					Text("not found")
						.font(.caption2)
						.foregroundColor(.secondary)
				}
			}
		}
	}

	private func transformRulesEditor(_ levelIndex: Int) -> some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack {
				Text("Search & Replace")
					.font(.caption)
					.foregroundColor(.secondary)
				Spacer()
				Button {
					settings.levels[levelIndex].transformRules.append(TOCTransformRule())
				} label: {
					Image(systemName: "plus.circle")
				}
				.buttonStyle(.plain)
			}
			ForEach(settings.levels[levelIndex].transformRules.indices, id: \.self) { ruleIndex in
				HStack(spacing: 6) {
					TextField("search", text: $settings.levels[levelIndex].transformRules[ruleIndex].search)
						.textFieldStyle(.roundedBorder)
					Image(systemName: "arrow.right")
						.font(.caption2)
						.foregroundColor(.secondary)
					TextField("replace", text: $settings.levels[levelIndex].transformRules[ruleIndex].replace)
						.textFieldStyle(.roundedBorder)
					Toggle("Regex", isOn: $settings.levels[levelIndex].transformRules[ruleIndex].isRegex)
						.toggleStyle(.checkbox)
						.font(.caption2)
					Button {
						settings.levels[levelIndex].transformRules.remove(at: ruleIndex)
					} label: {
						Image(systemName: "minus.circle")
					}
					.buttonStyle(.plain)
				}
			}
		}
	}
}
