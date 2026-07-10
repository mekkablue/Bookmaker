import SwiftUI

struct TypesetActionKey: FocusedValueKey {
	typealias Value = () -> Void
}

struct ShowPreviewKey: FocusedValueKey {
	typealias Value = Binding<Bool>
}

struct ShowPageSetupKey: FocusedValueKey {
	typealias Value = Binding<Bool>
}

struct ShowFontSettingsKey: FocusedValueKey {
	typealias Value = Binding<Bool>
}

struct AutoTypesetKey: FocusedValueKey {
	typealias Value = Binding<Bool>
}

extension FocusedValues {
	var typesetAction: TypesetActionKey.Value? {
		get { self[TypesetActionKey.self] }
		set { self[TypesetActionKey.self] = newValue }
	}

	var showPreview: ShowPreviewKey.Value? {
		get { self[ShowPreviewKey.self] }
		set { self[ShowPreviewKey.self] = newValue }
	}

	var showPageSetup: ShowPageSetupKey.Value? {
		get { self[ShowPageSetupKey.self] }
		set { self[ShowPageSetupKey.self] = newValue }
	}

	var showFontSettings: ShowFontSettingsKey.Value? {
		get { self[ShowFontSettingsKey.self] }
		set { self[ShowFontSettingsKey.self] = newValue }
	}

	var autoTypeset: AutoTypesetKey.Value? {
		get { self[AutoTypesetKey.self] }
		set { self[AutoTypesetKey.self] = newValue }
	}
}

/// Menu equivalents of the toolbar controls. Disabled when no book window has focus.
struct BookmakerCommands: Commands {
	@FocusedValue(\.typesetAction) private var typesetAction
	@FocusedValue(\.showPreview) private var showPreview
	@FocusedValue(\.showPageSetup) private var showPageSetup
	@FocusedValue(\.showFontSettings) private var showFontSettings
	@FocusedValue(\.autoTypeset) private var autoTypeset

	var body: some Commands {
		CommandGroup(after: .sidebar) {
			Button(showPreview?.wrappedValue == true ? "Hide PDF Preview" : "Show PDF Preview") {
				showPreview?.wrappedValue.toggle()
			}
			.keyboardShortcut("p", modifiers: [.command, .option])
			.disabled(showPreview == nil)

			Button(showPageSetup?.wrappedValue == true ? "Hide Page Setup" : "Show Page Setup") {
				showPageSetup?.wrappedValue.toggle()
			}
			.keyboardShortcut("m", modifiers: [.command, .option])
			.disabled(showPageSetup == nil)

			Button("Edit Fonts…") {
				showFontSettings?.wrappedValue = true
			}
			.keyboardShortcut("f", modifiers: [.command, .option])
			.disabled(showFontSettings == nil)

			Divider()
		}

		CommandMenu("Typeset") {
			Button("Typeset") {
				typesetAction?()
			}
			.keyboardShortcut("r", modifiers: .command)
			.disabled(typesetAction == nil)

			Toggle("Auto Typeset", isOn: autoTypeset ?? .constant(false))
				.disabled(autoTypeset == nil)
		}
	}
}
