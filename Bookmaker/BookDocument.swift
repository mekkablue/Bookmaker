import SwiftUI
import UniformTypeIdentifiers

extension UTType {
	static let bookmakerBook = UTType(exportedAs: "com.mekkablue.bookmaker.book")
}

struct PageSettings: Codable, Equatable {
	var paperWidth: Double = 148.0
	var paperHeight: Double = 210.0
	var marginTop: Double = 20.0
	var marginBottom: Double = 25.0
	var marginInner: Double = 22.0
	var marginOuter: Double = 18.0

	var geometryOptions: String {
		String(
			format: "paperwidth=%.5gmm, paperheight=%.5gmm, top=%.5gmm, bottom=%.5gmm, inner=%.5gmm, outer=%.5gmm",
			paperWidth, paperHeight, marginTop, marginBottom, marginInner, marginOuter
		)
	}
}

enum DefaultTemplates {
	/// Wrapper for the whole book: document class, page geometry, running headers.
	/// Placeholders: {{GEOMETRY}} (from page settings), {{FONTENCODING}} (fontenc or
	/// fontspec, decided document-wide), {{TEXTSTYLES}} (from the text styles
	/// catalog — font/size/color for every text type), {{PAGENUMBERS}} (from
	/// page number settings), {{FOOTNOTES}} (from footnote settings),
	/// {{CROSSREFERENCES}} (from cross-reference settings, only when the body
	/// actually uses one), {{TOC}} (TOC template), {{BODY}} (body text).
	static let spread = #"""
	\documentclass[11pt,twoside,openright]{book}
	{{FONTENCODING}}
	\usepackage[{{GEOMETRY}}]{geometry}
	{{TEXTSTYLES}}
	{{FOOTNOTES}}
	{{CROSSREFERENCES}}
	% running heads with page numbers, built into the book class;
	% needs no packages, so it works with the bundled TinyTeX unless you
	% choose a system or variable font, which needs a full TeX install
	% (e.g. MacTeX) with xelatex or lualatex.
	\pagestyle{headings}
	{{PAGENUMBERS}}

	\begin{document}

	{{TOC}}

	{{BODY}}

	\end{document}
	"""#

	/// Inserted where {{TOC}} appears in the spread template.
	static let toc = #"""
	\frontmatter
	\tableofcontents
	\mainmatter
	"""#

	static let sampleBody = #"""
	\chapter{The Shape of a Page}

	Every book begins not with its first sentence but with the shape of its page. The proportions of the paper, the weight of the margins, the width of the measure: these decisions are made before a single word is set, and they quietly govern everything that follows.

	\section{Margins}

	Margins are not empty space. They hold the thumbs of the reader, carry the running heads and folios, and balance the text block on the spread. A book set with generous inner margins opens comfortably; one set without them drowns its text in the gutter.

	Traditionally the inner margin is narrower than the outer, so that the two text blocks of a spread read as a single unit. The bottom margin is usually the largest, keeping the text block from appearing to slide off the page.

	\section{The Measure}

	A comfortable line holds somewhere between fifty and seventy characters. Wider, and the eye loses its way on the return sweep; narrower, and the text breaks into a nervous staccato of hyphens. Adjust the page margins in Bookmaker and watch the paragraphs reflow to the new measure.

	\chapter{Reflowing the Text}

	Change the page size or any margin and typeset again: the entire book reflows, the table of contents picks up the new page numbers, and the spreads settle into their new proportions. This is the whole point of separating content from layout.

	\section{Working with Templates}

	The spread template wraps the whole book: document class, geometry, running headers and footers. The TOC template decides how the front matter and table of contents are produced. Edit either one from the picker above the editor, or reset it to the built-in default.

	\section{What Comes Next}

	This first iteration keeps things deliberately small: no images, no chapter files, no styles beyond what the templates declare. Set your page, write your chapters, and typeset.
	"""#
}

struct BookDocument: FileDocument, Codable, Equatable {
	static var readableContentTypes: [UTType] { [.bookmakerBook] }

	var settings = PageSettings()
	var textStyles = TextStylesCatalog()
	var pageNumbers = PageNumberSettings()
	var footnotes = FootnoteSettings()
	var crossReferences = CrossReferenceSettings()
	var tocBuilder = TOCSettings()
	var spreadTemplate = DefaultTemplates.spread
	var tocTemplate = DefaultTemplates.toc
	var bodyText = DefaultTemplates.sampleBody

	init() {}

	private enum CodingKeys: String, CodingKey {
		case settings, textStyles, pageNumbers, footnotes, crossReferences, tocBuilder, spreadTemplate, tocTemplate, bodyText
	}

	/// Documents saved before "Edit Styles…" existed stored font choices
	/// separately per feature (`fonts.bodyFont`/`headingFont`/`captionFont`,
	/// `footnotes.font`, `pageNumbers.font`/`fontSize`). Reading those root
	/// keys directly (bypassing the now font-less current structs) migrates
	/// them into the new catalog on first open.
	private enum LegacyRootKeys: String, CodingKey {
		case fonts, footnotes, pageNumbers
	}

	private struct LegacyFontSettings: Decodable {
		var bodyFont: FontSelection?
		var headingFont: FontSelection?
		var captionFont: FontSelection?
	}

	private struct LegacyFootnoteFont: Decodable {
		var font: FontSelection?
	}

	private struct LegacyPageNumberFont: Decodable {
		var font: FontSelection?
		var fontSize: Double?
	}

	private static func migrateLegacyTextStyles(_ decoder: Decoder) -> TextStylesCatalog {
		var catalog = TextStylesCatalog()
		guard let legacyRoot = try? decoder.container(keyedBy: LegacyRootKeys.self) else {
			return catalog
		}
		if let legacyFonts = try? legacyRoot.decodeIfPresent(LegacyFontSettings.self, forKey: .fonts) {
			if let bodyFont = legacyFonts.bodyFont, bodyFont != .builtin(.computerModern) {
				catalog.body = .partial(PartialStyle(fontOverride: bodyFont))
			}
			if let headingFont = legacyFonts.headingFont, headingFont != .builtin(.computerModern) {
				catalog.heading = .partial(PartialStyle(fontOverride: headingFont))
			}
			if let captionFont = legacyFonts.captionFont, captionFont != .builtin(.computerModern) {
				catalog.caption = .partial(PartialStyle(fontOverride: captionFont))
			}
		}
		if let legacyFootnote = try? legacyRoot.decodeIfPresent(LegacyFootnoteFont.self, forKey: .footnotes),
		   let font = legacyFootnote.font, font != .builtin(.computerModern) {
			catalog.footnote = .partial(PartialStyle(fontOverride: font))
		}
		if let legacyPageNumber = try? legacyRoot.decodeIfPresent(LegacyPageNumberFont.self, forKey: .pageNumbers) {
			var partial = PartialStyle()
			if let font = legacyPageNumber.font, font != .builtin(.computerModern) {
				partial.fontOverride = font
			}
			if let size = legacyPageNumber.fontSize, size != 10 {
				partial.sizeAdjustment = .absolute(size)
			}
			if partial.isCustomized {
				catalog.pageNumber = .partial(partial)
			}
		}
		return catalog
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		settings = try container.decode(PageSettings.self, forKey: .settings)
		// documents saved before these settings existed simply have no such key
		if let existingStyles = try? container.decodeIfPresent(TextStylesCatalog.self, forKey: .textStyles) {
			textStyles = existingStyles
		} else {
			textStyles = Self.migrateLegacyTextStyles(decoder)
		}
		pageNumbers = try container.decodeIfPresent(PageNumberSettings.self, forKey: .pageNumbers) ?? PageNumberSettings()
		footnotes = try container.decodeIfPresent(FootnoteSettings.self, forKey: .footnotes) ?? FootnoteSettings()
		crossReferences = try container.decodeIfPresent(CrossReferenceSettings.self, forKey: .crossReferences) ?? CrossReferenceSettings()
		tocBuilder = try container.decodeIfPresent(TOCSettings.self, forKey: .tocBuilder) ?? TOCSettings()
		spreadTemplate = try container.decode(String.self, forKey: .spreadTemplate)
		tocTemplate = try container.decode(String.self, forKey: .tocTemplate)
		bodyText = try container.decode(String.self, forKey: .bodyText)
	}

	init(configuration: ReadConfiguration) throws {
		guard let data = configuration.file.regularFileContents else {
			throw CocoaError(.fileReadCorruptFile)
		}
		self = try JSONDecoder().decode(BookDocument.self, from: data)
	}

	func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		return FileWrapper(regularFileWithContents: try encoder.encode(self))
	}

	/// True when any text style's chosen font is a system font rather than
	/// a curated pdflatex-safe one, which pdflatex cannot render —
	/// compilation must switch to XeLaTeX.
	var requiresXeLaTeX: Bool {
		textStyles.usesSystemFont
	}

	/// True when the body text actually uses a varioref command, so the
	/// package is only loaded once a cross-reference has actually been inserted.
	private var usesCrossReferences: Bool {
		bodyText.contains(#"\vpageref"#) || bodyText.contains(#"\vref"#)
	}

	/// The complete LaTeX source: spread template with TOC, body, geometry,
	/// fonts, page numbers, footnotes and cross-references filled in.
	var assembledLaTeX: String {
		let fontEncoding = requiresXeLaTeX ? #"\usepackage{fontspec}"# : #"\usepackage[T1]{fontenc}"#
		return spreadTemplate
			.replacingOccurrences(of: "{{TOC}}", with: tocTemplate)
			.replacingOccurrences(of: "{{BODY}}", with: bodyText)
			.replacingOccurrences(of: "{{GEOMETRY}}", with: settings.geometryOptions + pageNumbers.geometryExtras)
			.replacingOccurrences(of: "{{FONTENCODING}}", with: fontEncoding)
			.replacingOccurrences(of: "{{TEXTSTYLES}}", with: textStyles.preamble)
			.replacingOccurrences(of: "{{FOOTNOTES}}", with: footnotes.preamble(styleIsCustomized: textStyles.footnote.isCustomized))
			.replacingOccurrences(of: "{{CROSSREFERENCES}}", with: usesCrossReferences ? crossReferences.preamble : "")
			.replacingOccurrences(of: "{{PAGENUMBERS}}", with: pageNumbers.preamble)
	}
}
