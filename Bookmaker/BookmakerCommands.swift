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

struct InsertFootnoteActionKey: FocusedValueKey {
	typealias Value = () -> Void
}

struct ShowFootnoteSettingsKey: FocusedValueKey {
	typealias Value = Binding<Bool>
}

struct InsertReferenceMarkActionKey: FocusedValueKey {
	typealias Value = () -> Void
}

struct ShowCrossReferenceInsertKey: FocusedValueKey {
	typealias Value = Binding<Bool>
}

struct ShowCrossReferenceSettingsKey: FocusedValueKey {
	typealias Value = Binding<Bool>
}

struct ShowTOCBuilderKey: FocusedValueKey {
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

	var insertFootnoteAction: InsertFootnoteActionKey.Value? {
		get { self[InsertFootnoteActionKey.self] }
		set { self[InsertFootnoteActionKey.self] = newValue }
	}

	var showFootnoteSettings: ShowFootnoteSettingsKey.Value? {
		get { self[ShowFootnoteSettingsKey.self] }
		set { self[ShowFootnoteSettingsKey.self] = newValue }
	}

	var insertReferenceMarkAction: InsertReferenceMarkActionKey.Value? {
		get { self[InsertReferenceMarkActionKey.self] }
		set { self[InsertReferenceMarkActionKey.self] = newValue }
	}

	var showCrossReferenceInsert: ShowCrossReferenceInsertKey.Value? {
		get { self[ShowCrossReferenceInsertKey.self] }
		set { self[ShowCrossReferenceInsertKey.self] = newValue }
	}

	var showCrossReferenceSettings: ShowCrossReferenceSettingsKey.Value? {
		get { self[ShowCrossReferenceSettingsKey.self] }
		set { self[ShowCrossReferenceSettingsKey.self] = newValue }
	}

	var showTOCBuilder: ShowTOCBuilderKey.Value? {
		get { self[ShowTOCBuilderKey.self] }
		set { self[ShowTOCBuilderKey.self] = newValue }
	}
}

/// Menu equivalents of the toolbar controls. Disabled when no book window has focus.
struct BookmakerCommands: Commands {
	@FocusedValue(\.typesetAction) private var typesetAction
	@FocusedValue(\.showPreview) private var showPreview
	@FocusedValue(\.showPageSetup) private var showPageSetup
	@FocusedValue(\.showFontSettings) private var showFontSettings
	@FocusedValue(\.autoTypeset) private var autoTypeset
	@FocusedValue(\.insertFootnoteAction) private var insertFootnoteAction
	@FocusedValue(\.showFootnoteSettings) private var showFootnoteSettings
	@FocusedValue(\.insertReferenceMarkAction) private var insertReferenceMarkAction
	@FocusedValue(\.showCrossReferenceInsert) private var showCrossReferenceInsert
	@FocusedValue(\.showCrossReferenceSettings) private var showCrossReferenceSettings
	@FocusedValue(\.showTOCBuilder) private var showTOCBuilder

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

			Button("Configure Footnotes…") {
				showFootnoteSettings?.wrappedValue = true
			}
			.keyboardShortcut("n", modifiers: [.command, .option, .shift])
			.disabled(showFootnoteSettings == nil)

			Button("Configure Cross-References…") {
				showCrossReferenceSettings?.wrappedValue = true
			}
			.keyboardShortcut("r", modifiers: [.command, .option, .shift])
			.disabled(showCrossReferenceSettings == nil)

			Button("Table of Contents…") {
				showTOCBuilder?.wrappedValue = true
			}
			.keyboardShortcut("t", modifiers: [.command, .option])
			.disabled(showTOCBuilder == nil)

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

		CommandMenu("Insert") {
			Button("Insert Footnote") {
				insertFootnoteAction?()
			}
			.keyboardShortcut("n", modifiers: [.command, .option])
			.disabled(insertFootnoteAction == nil)

			Button("Insert Reference Mark") {
				insertReferenceMarkAction?()
			}
			.keyboardShortcut("l", modifiers: [.command, .option])
			.disabled(insertReferenceMarkAction == nil)

			Button("Insert Cross-Reference…") {
				showCrossReferenceInsert?.wrappedValue = true
			}
			.keyboardShortcut("r", modifiers: [.command, .option])
			.disabled(showCrossReferenceInsert == nil)
		}
	}
}
