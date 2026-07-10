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
	/// Placeholders: {{GEOMETRY}} (from page settings), {{FONTS}} (from font settings),
	/// {{TOC}} (TOC template), {{BODY}} (body text).
	static let spread = #"""
	\documentclass[11pt,twoside,openright]{book}
	\usepackage[T1]{fontenc}
	\usepackage[{{GEOMETRY}}]{geometry}
	{{FONTS}}
	% running heads with page numbers, built into the book class;
	% needs no packages, so it works with the bundled TinyTeX.
	% With a full MacTeX you can switch to \usepackage{fancyhdr} here.
	\pagestyle{headings}

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
	var fonts = FontSettings()
	var spreadTemplate = DefaultTemplates.spread
	var tocTemplate = DefaultTemplates.toc
	var bodyText = DefaultTemplates.sampleBody

	init() {}

	private enum CodingKeys: String, CodingKey {
		case settings, fonts, spreadTemplate, tocTemplate, bodyText
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		settings = try container.decode(PageSettings.self, forKey: .settings)
		// documents saved before font settings existed simply have no "fonts" key
		fonts = try container.decodeIfPresent(FontSettings.self, forKey: .fonts) ?? FontSettings()
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

	/// The complete LaTeX source: spread template with TOC, body and geometry filled in.
	var assembledLaTeX: String {
		spreadTemplate
			.replacingOccurrences(of: "{{TOC}}", with: tocTemplate)
			.replacingOccurrences(of: "{{BODY}}", with: bodyText)
			.replacingOccurrences(of: "{{GEOMETRY}}", with: settings.geometryOptions)
			.replacingOccurrences(of: "{{FONTS}}", with: fonts.preamble)
	}
}
