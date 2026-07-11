import SwiftUI
import PDFKit

struct ContentView: View {
	@Binding var document: BookDocument
	@StateObject private var typesetter = TypesetController()
	@StateObject private var installer = LaTeXInstaller()
	@State private var editorMode: EditorMode = .text
	@State private var editedSource: EditedSource = .bodyText
	@State private var previewMode: PreviewMode = .spreads
	@State private var showPreview = true
	@State private var showPageSetup = true
	@State private var showFontSettings = false
	@State private var showFootnoteSettings = false
	@State private var showCrossReferenceSettings = false
	@State private var showCrossReferenceInsert = false
	@State private var autoTypeset = true
	@State private var showLog = false
	@State private var pendingTypeset: Task<Void, Never>?
	@State private var pendingBodySnippet: EditorSnippet?

	enum EditorMode: String, CaseIterable, Identifiable {
		case text = "Text"
		case gui = "GUI"
		var id: String { rawValue }
	}

	enum EditedSource: String, CaseIterable, Identifiable {
		case bodyText = "Body"
		case spreadTemplate = "Spread Template"
		case tocTemplate = "TOC Template"
		var id: String { rawValue }
	}

	enum PreviewMode: String, CaseIterable, Identifiable {
		case singlePages = "Single Pages"
		case spreads = "Spreads"
		var id: String { rawValue }
		var pdfDisplayMode: PDFDisplayMode {
			self == .spreads ? .twoUpContinuous : .singlePageContinuous
		}
	}

	var body: some View {
		HSplitView {
			editorPane
				.frame(minWidth: 350, maxWidth: .infinity, maxHeight: .infinity)
			if showPreview {
				previewPane
					.frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
			}
		}
		.toolbar {
			ToolbarItemGroup {
				if typesetter.isTypesetting {
					ProgressView()
						.controlSize(.small)
				}
				Button {
					typeset()
				} label: {
					Label("Typeset", systemImage: "play.fill")
				}
				.help("Typeset the book (⌘R)")
				.disabled(typesetter.isTypesetting)
				Toggle(isOn: $autoTypeset) {
					Label("Auto Typeset", systemImage: "arrow.triangle.2.circlepath")
				}
				.help("Automatically typeset after every change")
				Toggle(isOn: $showPageSetup) {
					Label("Page Setup", systemImage: "ruler")
				}
				.help("Show page size and margins")
				Toggle(isOn: $showPreview) {
					Label("Preview", systemImage: "sidebar.right")
				}
				.help("Show the PDF preview in a split view")
			}
		}
		.focusedSceneValue(\.typesetAction, typeset)
		.focusedSceneValue(\.showPreview, $showPreview)
		.focusedSceneValue(\.showPageSetup, $showPageSetup)
		.focusedSceneValue(\.showFontSettings, $showFontSettings)
		.focusedSceneValue(\.autoTypeset, $autoTypeset)
		.focusedSceneValue(\.insertFootnoteAction, insertFootnote)
		.focusedSceneValue(\.showFootnoteSettings, $showFootnoteSettings)
		.focusedSceneValue(\.insertReferenceMarkAction, insertReferenceMark)
		.focusedSceneValue(\.showCrossReferenceInsert, $showCrossReferenceInsert)
		.focusedSceneValue(\.showCrossReferenceSettings, $showCrossReferenceSettings)
		.sheet(isPresented: $showFontSettings) {
			FontSettingsView(fonts: $document.fonts)
		}
		.sheet(isPresented: $showFootnoteSettings) {
			FootnoteSettingsView(footnotes: $document.footnotes)
		}
		.sheet(isPresented: $showCrossReferenceSettings) {
			CrossReferenceSettingsView(crossReferences: $document.crossReferences)
		}
		.sheet(isPresented: $showCrossReferenceInsert) {
			CrossReferenceInsertView(bodyText: document.bodyText, introWord: document.crossReferences.introWord) { label in
				let text = document.crossReferences.referenceSnippet(to: label)
				insertIntoBody(EditorSnippet(text: text, caretOffset: text.count))
			}
		}
		.onAppear {
			typeset()
		}
		.onChange(of: document) { _ in
			scheduleAutoTypeset()
		}
	}

	// MARK: - Editor

	private var editorPane: some View {
		VStack(spacing: 0) {
			HStack {
				Picker("", selection: $editorMode) {
					ForEach(EditorMode.allCases) { mode in
						Text(mode.rawValue).tag(mode)
					}
				}
				.pickerStyle(.segmented)
				.labelsHidden()
				.frame(width: 130)
				if editorMode == .text {
					Divider().frame(height: 16)
					Picker("", selection: $editedSource) {
						ForEach(EditedSource.allCases) { source in
							Text(source.rawValue).tag(source)
						}
					}
					.pickerStyle(.segmented)
					.labelsHidden()
					if editedSource != .bodyText {
						Button("Reset to Default") {
							resetCurrentTemplate()
						}
						.help("Replace this template with the built-in default")
					}
				}
			}
			.padding(8)
			Divider()
			if editorMode == .text {
				LaTeXEditor(text: sourceBinding, pendingSnippet: editedSource == .bodyText ? $pendingBodySnippet : .constant(nil))
				if showPageSetup {
					Divider()
					PageSetupView(settings: $document.settings)
				}
			} else {
				GUICanvasView(
					settings: $document.settings,
					bodyText: $document.bodyText,
					pageNumbers: $document.pageNumbers,
					crossReferences: document.crossReferences
				)
			}
		}
	}

	private var sourceBinding: Binding<String> {
		switch editedSource {
		case .bodyText:
			return $document.bodyText
		case .spreadTemplate:
			return $document.spreadTemplate
		case .tocTemplate:
			return $document.tocTemplate
		}
	}

	private func resetCurrentTemplate() {
		switch editedSource {
		case .spreadTemplate:
			document.spreadTemplate = DefaultTemplates.spread
		case .tocTemplate:
			document.tocTemplate = DefaultTemplates.toc
		case .bodyText:
			break
		}
	}

	// MARK: - Footnotes & cross-references

	private func insertFootnote() {
		let text = #"\footnote{}"#
		insertIntoBody(EditorSnippet(text: text, caretOffset: text.count - 1))
	}

	private func insertReferenceMark() {
		let name = LabelScanner.nextMarkName(in: document.bodyText)
		let text = "\\label{\(name)}"
		insertIntoBody(EditorSnippet(text: text, caretOffset: text.count))
	}

	/// Inserts at the cursor when the body editor is visible and focused;
	/// otherwise brings it into view and appends, since there is no
	/// meaningful cursor position to target.
	private func insertIntoBody(_ snippet: EditorSnippet) {
		if editorMode == .text, editedSource == .bodyText {
			pendingBodySnippet = snippet
		} else {
			editorMode = .text
			editedSource = .bodyText
			let separator = document.bodyText.isEmpty || document.bodyText.hasSuffix("\n\n") ? "" : "\n\n"
			document.bodyText += separator + snippet.text
		}
	}

	// MARK: - Preview

	private var previewPane: some View {
		VStack(spacing: 0) {
			HStack {
				Picker("", selection: $previewMode) {
					ForEach(PreviewMode.allCases) { mode in
						Text(mode.rawValue).tag(mode)
					}
				}
				.pickerStyle(.segmented)
				.labelsHidden()
				.frame(width: 200)
				Spacer()
				if let pdf = typesetter.pdfDocument {
					Text("\(pdf.pageCount) pages")
						.font(.caption)
						.foregroundColor(.secondary)
				}
			}
			.padding(8)
			Divider()
			if typesetter.engineMissing, document.requiresXeLaTeX {
				xelatexMissingView
			} else if typesetter.engineMissing {
				LaTeXInstallView(installer: installer) {
					typeset()
				}
			} else if let pdf = typesetter.pdfDocument {
				PDFPreviewView(document: pdf, displayMode: previewMode.pdfDisplayMode)
			} else if typesetter.isTypesetting {
				Spacer()
				ProgressView("Typesetting…")
				Spacer()
			} else {
				Spacer()
				Text("Press Typeset (⌘R) to build the PDF preview.")
					.foregroundColor(.secondary)
				Spacer()
			}
			if let error = typesetter.lastError, !typesetter.engineMissing {
				Divider()
				errorBar(error)
			}
		}
	}

	private var xelatexMissingView: some View {
		VStack(spacing: 12) {
			Image(systemName: "textformat.characters")
				.font(.system(size: 36))
				.foregroundColor(.secondary)
			Text("Needs a Full TeX Install")
				.font(.headline)
			Text("This document uses a system or variable font, which needs XeLaTeX or LuaLaTeX to typeset. The bundled TinyTeX only provides pdflatex — install a full TeX distribution such as MacTeX, or switch every font back to a built-in one in Edit Fonts, Page Numbers, and Configure Footnotes.")
				.font(.caption)
				.foregroundColor(.secondary)
				.multilineTextAlignment(.center)
				.frame(maxWidth: 340)
			Link("Get MacTeX…", destination: URL(string: "https://tug.org/mactex/")!)
				.font(.caption)
			Button("Try Again") {
				typeset()
			}
			.keyboardShortcut(.defaultAction)
		}
		.padding(20)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}

	private func errorBar(_ error: String) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack {
				Image(systemName: "exclamationmark.triangle.fill")
					.foregroundColor(.yellow)
				Text(error)
					.font(.caption)
					.lineLimit(2)
					.textSelection(.enabled)
				Spacer()
				if !typesetter.log.isEmpty {
					Button(showLog ? "Hide Log" : "Show Log") {
						showLog.toggle()
					}
					.controlSize(.small)
				}
			}
			if showLog {
				ScrollView {
					Text(typesetter.log)
						.font(.system(size: 10, design: .monospaced))
						.textSelection(.enabled)
						.frame(maxWidth: .infinity, alignment: .leading)
				}
				.frame(height: 160)
			}
		}
		.padding(8)
	}

	// MARK: - Typesetting

	private func typeset() {
		pendingTypeset?.cancel()
		let engine: LaTeXEngineKind = document.requiresXeLaTeX ? .xelatex : .pdflatex
		typesetter.typeset(source: document.assembledLaTeX, engine: engine)
	}

	private func scheduleAutoTypeset() {
		guard autoTypeset else {
			return
		}
		pendingTypeset?.cancel()
		pendingTypeset = Task {
			try? await Task.sleep(nanoseconds: 1_200_000_000)
			if !Task.isCancelled {
				typeset()
			}
		}
	}
}
