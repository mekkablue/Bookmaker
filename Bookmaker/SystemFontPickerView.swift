import SwiftUI

/// Lets the user choose any font installed on this Mac. Variable fonts show
/// one slider per STAT axis instead of a flat list of every named style.
struct SystemFontPickerView: View {
	var onSelect: (SystemFontSelection) -> Void
	@Environment(\.dismiss) private var dismiss

	@State private var familyNames: [String] = []
	@State private var searchText = ""
	@State private var selectedFamily: String?
	@State private var faces: [VariableFontIntrospector.FaceInfo] = []
	@State private var selectedFaceID: String?
	@State private var axisValues: [String: Double] = [:]

	var body: some View {
		HSplitView {
			familyList
				.frame(minWidth: 220, maxWidth: 280)
			detail
				.frame(minWidth: 460, maxWidth: .infinity)
		}
		// wide enough that a variable font's axis sliders (420pt by default,
		// widened further via their own resize handle) aren't cut off
		.frame(minWidth: 760, minHeight: 480)
		.onAppear {
			familyNames = SystemFontCatalog.familyNames()
		}
	}

	private var filteredFamilies: [String] {
		guard !searchText.isEmpty else {
			return familyNames
		}
		return familyNames.filter { $0.localizedCaseInsensitiveContains(searchText) }
	}

	private var selectedFace: VariableFontIntrospector.FaceInfo? {
		faces.first { $0.id == selectedFaceID }
	}

	private var familyList: some View {
		VStack(spacing: 0) {
			TextField("Search Fonts", text: $searchText)
				.textFieldStyle(.roundedBorder)
				.padding(8)
			List(filteredFamilies, id: \.self, selection: $selectedFamily) { family in
				Text(family).tag(family)
			}
			.onChange(of: selectedFamily) { family in
				guard let family = family else {
					faces = []
					selectedFaceID = nil
					return
				}
				faces = SystemFontCatalog.faces(inFamily: family).map(VariableFontIntrospector.introspect)
				selectedFaceID = faces.first?.id
				axisValues = [:]
			}
		}
	}

	private var detail: some View {
		VStack(alignment: .leading, spacing: 12) {
			if let family = selectedFamily {
				Text(family)
					.font(.title3.bold())
				if faces.count > 1 {
					Picker("Face", selection: $selectedFaceID) {
						ForEach(faces) { face in
							Text(face.displayName + (face.isVariable ? " (Variable)" : "")).tag(Optional(face.id))
						}
					}
					.labelsHidden()
					.onChange(of: selectedFaceID) { _ in
						axisValues = [:]
					}
				}
				if let face = selectedFace {
					if face.isVariable, !face.axes.isEmpty {
						// horizontal scroll too, so widening the sliders via their own
						// resize handle beyond the sheet's width stays reachable
						ScrollView([.horizontal, .vertical]) {
							VariableFontAxesView(axes: face.axes, values: $axisValues)
								.padding(.vertical, 8)
						}
					} else {
						Text("A standard, non-variable font.")
							.font(.caption)
							.foregroundColor(.secondary)
					}
				}
				Spacer()
				HStack {
					Spacer()
					Button("Cancel") {
						dismiss()
					}
					Button("Choose") {
						guard let face = selectedFace else {
							return
						}
						onSelect(SystemFontSelection(
							postscriptName: face.postscriptName,
							familyName: family,
							displayName: face.displayName,
							isVariable: face.isVariable,
							axisValues: axisValues
						))
						dismiss()
					}
					.keyboardShortcut(.defaultAction)
					.disabled(selectedFace == nil)
				}
			} else {
				Spacer()
				Text("Select a font family.")
					.foregroundColor(.secondary)
				Spacer()
			}
		}
		.padding(16)
	}
}
