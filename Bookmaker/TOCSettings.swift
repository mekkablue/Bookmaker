import Foundation

/// One heading found in the compiled book's table of contents, parsed from
/// pdflatex/xelatex's own generated main.toc — so the page number is
/// whatever LaTeX actually computed, not a guess.
struct TOCEntry: Identifiable, Equatable {
	var id = UUID()
	var level: String   // "part", "chapter", "section", "subsection", "subsubsection"
	var text: String    // raw LaTeX, e.g. "\numberline {1}The Shape of a Page"
	var page: Int
}

/// Parses a LaTeX .toc file's `\contentsline` entries. Brace-matched by hand
/// rather than a single regex, since the title argument routinely contains
/// nested braces (`\numberline {1}Title`, `\textit{...}`, etc.).
enum TOCFileParser {
	static func parseFile(at url: URL) -> [TOCEntry] {
		guard let text = try? String(contentsOf: url, encoding: .utf8) else {
			return []
		}
		return parse(text)
	}

	static func parse(_ text: String) -> [TOCEntry] {
		var entries: [TOCEntry] = []
		var searchStart = text.startIndex
		while let markerRange = text.range(of: #"\contentsline"#, range: searchStart..<text.endIndex) {
			var cursor = markerRange.upperBound
			var groups: [String] = []
			while groups.count < 4, let group = readBraceGroup(text, from: &cursor) {
				groups.append(group)
			}
			if groups.count >= 3, let page = Int(groups[2].trimmingCharacters(in: .whitespaces)) {
				entries.append(TOCEntry(level: groups[0], text: groups[1], page: page))
			}
			searchStart = cursor
		}
		return entries
	}

	/// Skips whitespace, then reads one brace-delimited group at `cursor`,
	/// honoring nested braces. Advances `cursor` past it and returns the
	/// group's contents, or leaves `cursor` unchanged and returns nil if the
	/// next non-whitespace character isn't "{".
	private static func readBraceGroup(_ text: String, from cursor: inout String.Index) -> String? {
		var scan = cursor
		while scan < text.endIndex, text[scan].isWhitespace {
			scan = text.index(after: scan)
		}
		guard scan < text.endIndex, text[scan] == "{" else {
			return nil
		}
		var depth = 0
		var contentStart: String.Index?
		var i = scan
		while i < text.endIndex {
			let ch = text[i]
			if ch == "{" {
				if depth == 0 {
					contentStart = text.index(after: i)
				}
				depth += 1
			} else if ch == "}" {
				depth -= 1
				if depth == 0, let start = contentStart {
					let content = String(text[start..<i])
					cursor = text.index(after: i)
					return content
				}
			}
			i = text.index(after: i)
		}
		return nil
	}
}

/// A single search-and-replace step applied to a heading's extracted text,
/// e.g. to collapse embedded newlines or strip unwanted markup. Rules chain:
/// each runs on the previous rule's result, so
/// `[(search: "\n", replace: " "), (search: "  ", replace: " ")]` and a
/// single rule sharing one replacement across several search patterns come
/// out equivalent — this app only offers the flat, chained form, since any
/// grouped shorthand expands losslessly into it.
struct TOCTransformRule: Codable, Equatable, Identifiable {
	var id = UUID()
	var search = ""
	var replace = ""
	var isRegex = false

	func apply(to text: String) -> String {
		guard !search.isEmpty else {
			return text
		}
		if isRegex, let regex = try? NSRegularExpression(pattern: search) {
			let range = NSRange(text.startIndex..., in: text)
			return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replace)
		}
		return text.replacingOccurrences(of: search, with: replace)
	}
}

/// How one heading level (chapter, section, ...) is rendered into a custom,
/// hand-formatted table of contents line.
struct TOCLevelSettings: Codable, Equatable {
	var level: String
	var displayName: String
	var isIncluded = false
	/// <TEXT> and <PAGE> are substituted; \t becomes a literal tab character.
	/// This is inserted directly into the TOC template as LaTeX source, so
	/// e.g. \dotfill or \hfill compile normally — a raw tab renders as plain
	/// whitespace unless you set up your own tabbing/tabular around it.
	var lineTemplate = #"\t<TEXT>\t<PAGE>"#
	var transformRules: [TOCTransformRule] = []

	func formattedLine(for entry: TOCEntry) -> String {
		let cleanedText = transformRules.reduce(entry.text) { $1.apply(to: $0) }
		return lineTemplate
			.replacingOccurrences(of: "<TEXT>", with: cleanedText)
			.replacingOccurrences(of: "<PAGE>", with: String(entry.page))
			.replacingOccurrences(of: #"\t"#, with: "\t")
	}
}

/// Settings for the custom table of contents builder. Separate from LaTeX's
/// own automatic `\tableofcontents`: this reads the headings and page
/// numbers pdflatex/xelatex already computed (from main.toc) and lets you
/// write your own line format per heading level instead.
struct TOCSettings: Codable, Equatable {
	var levels: [TOCLevelSettings] = TOCSettings.defaultLevels

	static let defaultLevels: [TOCLevelSettings] = [
		TOCLevelSettings(level: "part", displayName: "Part"),
		TOCLevelSettings(level: "chapter", displayName: "Chapter", isIncluded: true),
		TOCLevelSettings(level: "section", displayName: "Section"),
		TOCLevelSettings(level: "subsection", displayName: "Subsection"),
		TOCLevelSettings(level: "subsubsection", displayName: "Subsubsection"),
	]

	/// The generated block of LaTeX: one line per included, matched heading,
	/// in document order, separated by explicit LaTeX line breaks.
	func generate(from entries: [TOCEntry]) -> String {
		let lines = entries.compactMap { entry -> String? in
			guard let level = levels.first(where: { $0.level == entry.level && $0.isIncluded }) else {
				return nil
			}
			return level.formattedLine(for: entry)
		}
		guard !lines.isEmpty else {
			return ""
		}
		return "\\noindent\n" + lines.joined(separator: " \\\\\n")
	}
}
