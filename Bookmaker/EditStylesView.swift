import SwiftUI
import AppKit

/// "Edit Styles…" window: every text type the document distinguishes, each
/// assignable either a full style (a complete, self-contained font/size/
/// color) or a partial style (only the differences from what it would
/// otherwise be — an optional font override, a discrete or relative size
/// change, an optional color).
struct EditStylesView: View {
	@Binding var textStyles: TextStylesCatalog
	@Environment(\.dismiss) private var dismiss

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			Text("Edit Styles")
				.font(.title2.bold())

			ScrollView {
				VStack(alignment: .leading, spacing: 18) {
					ForEach(TextStyleRole.allCases) { role in
						RoleStyleEditor(
							role: role,
							style: Binding(
								get: { textStyles.style(for: role) },
								set: { textStyles.setStyle($0, for: role) }
							)
						)
						if role != TextStyleRole.allCases.last {
							Divider()
						}
					}
				}
			}
			.frame(maxHeight: 460)

			HStack {
				Spacer()
				Button("Done") {
					dismiss()
				}
				.keyboardShortcut(.defaultAction)
			}
		}
		.padding(20)
		.frame(width: 520)
	}
}

private enum StyleMode: String, CaseIterable, Identifiable {
	case partial = "Partial"
	case full = "Full"
	var id: String { rawValue }
}

private enum SizeMode: String, CaseIterable, Identifiable {
	case unchanged = "Unchanged"
	case absolute = "Discrete (pt)"
	case multiply = "Relative (×)"
	case add = "Relative (+pt)"
	var id: String { rawValue }
}

private struct RoleStyleEditor: View {
	let role: TextStyleRole
	@Binding var style: TextStyle

	@State private var showingFontPicker = false

	private var mode: StyleMode {
		if case .full = style { return .full }
		return .partial
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack {
				Text(role.rawValue)
					.font(.headline)
				Spacer()
				Picker("", selection: modeBinding) {
					ForEach(StyleMode.allCases) { mode in
						Text(mode.rawValue).tag(mode)
					}
				}
				.labelsHidden()
				.frame(width: 110)
			}
			Text(role.hint)
				.font(.caption)
				.foregroundColor(.secondary)

			switch style {
			case .full(let full):
				fullEditor(full)
			case .partial(let partial):
				partialEditor(partial)
			}
		}
		.sheet(isPresented: $showingFontPicker) {
			SystemFontPickerView { chosen in
				setFont(.system(chosen))
			}
		}
	}

	private var modeBinding: Binding<StyleMode> {
		Binding(
			get: { mode },
			set: { newMode in
				switch newMode {
				case .full:
					if case .partial = style {
						style = .full(FullStyle())
					}
				case .partial:
					if case .full = style {
						style = .partial(PartialStyle())
					}
				}
			}
		)
	}

	private func setFont(_ font: FontSelection) {
		switch style {
		case .full(var full):
			full.font = font
			style = .full(full)
		case .partial(var partial):
			partial.fontOverride = font
			style = .partial(partial)
		}
	}

	@ViewBuilder
	private func fullEditor(_ full: FullStyle) -> some View {
		HStack {
			Text("Font")
				.frame(width: 70, alignment: .leading)
			fontLabel(full.font)
			Button("Choose System Font…") {
				showingFontPicker = true
			}
			.controlSize(.small)
		}
		HStack {
			Text("Size")
				.frame(width: 70, alignment: .leading)
			TextField("", value: fullSizeBinding, format: .number)
				.textFieldStyle(.roundedBorder)
				.frame(width: 52)
			Text("pt")
				.font(.caption)
				.foregroundColor(.secondary)
		}
		colorRow(
			isOn: full.color != nil,
			color: full.color ?? StyleColor(),
			setColor: { color in
				var updated = full
				updated.color = color
				style = .full(updated)
			},
			clearColor: {
				var updated = full
				updated.color = nil
				style = .full(updated)
			}
		)
	}

	@ViewBuilder
	private func partialEditor(_ partial: PartialStyle) -> some View {
		HStack {
			Text("Font")
				.frame(width: 70, alignment: .leading)
			if let font = partial.fontOverride {
				fontLabel(font)
				Button("Change…") {
					showingFontPicker = true
				}
				.controlSize(.small)
				Button("Clear") {
					var updated = partial
					updated.fontOverride = nil
					style = .partial(updated)
				}
				.controlSize(.small)
			} else {
				Text("Inherited")
					.foregroundColor(.secondary)
					.frame(width: 170, alignment: .leading)
				Button("Choose System Font…") {
					showingFontPicker = true
				}
				.controlSize(.small)
				Menu("Builtin…") {
					ForEach(FontChoice.allCases) { choice in
						Button(choice.rawValue) {
							setFont(.builtin(choice))
						}
					}
				}
				.controlSize(.small)
				.fixedSize()
			}
		}
		HStack {
			Text("Size")
				.frame(width: 70, alignment: .leading)
			Picker("", selection: sizeModeBinding) {
				ForEach(SizeMode.allCases) { mode in
					Text(mode.rawValue).tag(mode)
				}
			}
			.labelsHidden()
			.frame(width: 140)
			if sizeMode != .unchanged {
				TextField("", value: sizeValueBinding, format: .number)
					.textFieldStyle(.roundedBorder)
					.frame(width: 52)
			}
		}
		colorRow(
			isOn: partial.color != nil,
			color: partial.color ?? StyleColor(),
			setColor: { color in
				var updated = partial
				updated.color = color
				style = .partial(updated)
			},
			clearColor: {
				var updated = partial
				updated.color = nil
				style = .partial(updated)
			}
		)
	}

	private var fullSizeBinding: Binding<Double> {
		Binding(
			get: {
				if case .full(let full) = style { return full.sizePt }
				return 11
			},
			set: { newValue in
				if case .full(var full) = style {
					full.sizePt = newValue
					style = .full(full)
				}
			}
		)
	}

	private var sizeMode: SizeMode {
		guard case .partial(let partial) = style else { return .unchanged }
		switch partial.sizeAdjustment {
		case .unchanged: return .unchanged
		case .absolute: return .absolute
		case .multiply: return .multiply
		case .add: return .add
		}
	}

	private var sizeModeBinding: Binding<SizeMode> {
		Binding(
			get: { sizeMode },
			set: { newMode in
				guard case .partial(var partial) = style else { return }
				switch newMode {
				case .unchanged: partial.sizeAdjustment = .unchanged
				case .absolute: partial.sizeAdjustment = .absolute(12)
				case .multiply: partial.sizeAdjustment = .multiply(1.5)
				case .add: partial.sizeAdjustment = .add(2)
				}
				style = .partial(partial)
			}
		)
	}

	private var sizeValueBinding: Binding<Double> {
		Binding(
			get: {
				guard case .partial(let partial) = style else { return 0 }
				switch partial.sizeAdjustment {
				case .unchanged: return 0
				case .absolute(let value), .multiply(let value), .add(let value): return value
				}
			},
			set: { newValue in
				guard case .partial(var partial) = style else { return }
				switch partial.sizeAdjustment {
				case .unchanged: break
				case .absolute: partial.sizeAdjustment = .absolute(newValue)
				case .multiply: partial.sizeAdjustment = .multiply(newValue)
				case .add: partial.sizeAdjustment = .add(newValue)
				}
				style = .partial(partial)
			}
		)
	}

	private func fontLabel(_ font: FontSelection) -> some View {
		Group {
			switch font {
			case .builtin(let choice):
				Text(choice.rawValue)
					.lineLimit(1)
					.frame(width: 170, alignment: .leading)
			case .system(let system):
				Text(system.displayName)
					.lineLimit(1)
					.frame(width: 170, alignment: .leading)
			}
		}
	}

	@ViewBuilder
	private func colorRow(isOn: Bool, color: StyleColor, setColor: @escaping (StyleColor) -> Void, clearColor: @escaping () -> Void) -> some View {
		HStack {
			Text("Color")
				.frame(width: 70, alignment: .leading)
			Toggle("", isOn: Binding(
				get: { isOn },
				set: { newValue in
					if newValue {
						setColor(color)
					} else {
						clearColor()
					}
				}
			))
			.labelsHidden()
			.toggleStyle(.checkbox)
			if isOn {
				ColorPicker("", selection: Binding(
					get: { Color(red: color.red, green: color.green, blue: color.blue) },
					set: { newColor in
						let rgb = NSColor(newColor).usingColorSpace(.deviceRGB) ?? NSColor(red: 0, green: 0, blue: 0, alpha: 1)
						setColor(StyleColor(red: Double(rgb.redComponent), green: Double(rgb.greenComponent), blue: Double(rgb.blueComponent)))
					}
				))
				.labelsHidden()
			} else {
				Text("Inherited")
					.foregroundColor(.secondary)
			}
		}
	}
}
