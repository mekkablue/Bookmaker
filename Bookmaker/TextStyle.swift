import Foundation

/// How a role's font size relates to the document's body text size — either
/// left alone, pinned to a specific point size, or computed from body size
/// via a multiplier or an additive offset.
enum StyleSizeAdjustment: Codable, Equatable {
	case unchanged
	case absolute(Double)
	case multiply(Double)
	case add(Double)

	private enum Kind: String, Codable {
		case unchanged, absolute, multiply, add
	}

	private enum CodingKeys: String, CodingKey {
		case kind, value
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		switch try container.decode(Kind.self, forKey: .kind) {
		case .unchanged:
			self = .unchanged
		case .absolute:
			self = .absolute(try container.decode(Double.self, forKey: .value))
		case .multiply:
			self = .multiply(try container.decode(Double.self, forKey: .value))
		case .add:
			self = .add(try container.decode(Double.self, forKey: .value))
		}
	}

	func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		switch self {
		case .unchanged:
			try container.encode(Kind.unchanged, forKey: .kind)
		case .absolute(let value):
			try container.encode(Kind.absolute, forKey: .kind)
			try container.encode(value, forKey: .value)
		case .multiply(let value):
			try container.encode(Kind.multiply, forKey: .kind)
			try container.encode(value, forKey: .value)
		case .add(let value):
			try container.encode(Kind.add, forKey: .kind)
			try container.encode(value, forKey: .value)
		}
	}

	/// Resolves to a concrete point size, given the size it would otherwise be.
	func resolved(otherwise basePt: Double) -> Double {
		switch self {
		case .unchanged: return basePt
		case .absolute(let pt): return pt
		case .multiply(let factor): return basePt * factor
		case .add(let delta): return basePt + delta
		}
	}
}

/// An RGB color for LaTeX text, via the xcolor package.
struct StyleColor: Codable, Equatable {
	var red: Double = 0
	var green: Double = 0
	var blue: Double = 0

	/// The `\color{...}` argument, e.g. `[rgb]{0.800,0.100,0.100}`.
	var latexColorArgument: String {
		"[rgb]{\(Self.fmt(red)),\(Self.fmt(green)),\(Self.fmt(blue))}"
	}

	private static func fmt(_ value: Double) -> String {
		String(format: "%.3f", min(max(value, 0), 1))
	}
}

/// A complete style: everything LaTeX needs to typeset this text type from
/// scratch, independent of whatever else is going on around it.
struct FullStyle: Codable, Equatable {
	var font: FontSelection = .builtin(.computerModern)
	var sizePt: Double = 11
	var color: StyleColor?
}

/// A style expressed only as the difference from whatever this text type
/// would otherwise be — leaving any part unset means "inherit that part".
struct PartialStyle: Codable, Equatable {
	var fontOverride: FontSelection?
	var sizeAdjustment: StyleSizeAdjustment = .unchanged
	var color: StyleColor?

	var isCustomized: Bool {
		fontOverride != nil || color != nil || sizeAdjustment != .unchanged
	}
}

/// Either a full, self-contained style, or a partial one that only overrides
/// part of whatever the text type would otherwise look like.
enum TextStyle: Codable, Equatable {
	case full(FullStyle)
	case partial(PartialStyle)

	private enum Kind: String, Codable {
		case full, partial
	}

	private enum CodingKeys: String, CodingKey {
		case kind, full, partial
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		switch try container.decode(Kind.self, forKey: .kind) {
		case .full:
			self = .full(try container.decode(FullStyle.self, forKey: .full))
		case .partial:
			self = .partial(try container.decode(PartialStyle.self, forKey: .partial))
		}
	}

	func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		switch self {
		case .full(let style):
			try container.encode(Kind.full, forKey: .kind)
			try container.encode(style, forKey: .full)
		case .partial(let style):
			try container.encode(Kind.partial, forKey: .kind)
			try container.encode(style, forKey: .partial)
		}
	}

	var isCustomized: Bool {
		switch self {
		case .full: return true
		case .partial(let style): return style.isCustomized
		}
	}

	var usesSystemFont: Bool {
		let font: FontSelection?
		switch self {
		case .full(let style): font = style.font
		case .partial(let style): font = style.fontOverride
		}
		if case .system = font {
			return true
		}
		return false
	}
}

/// The text types Bookmaker distinguishes when typesetting a book.
enum TextStyleRole: String, CaseIterable, Identifiable {
	case body = "Body Text"
	case heading = "Headings"
	case caption = "Captions"
	case footnote = "Footnotes"
	case pageNumber = "Page Numbers"

	var id: String { rawValue }

	var macroName: String {
		switch self {
		case .body: return "bodystyle"
		case .heading: return "headingstyle"
		case .caption: return "captionstyle"
		case .footnote: return "footnotestyle"
		case .pageNumber: return "pagenumberstyle"
		}
	}

	var hint: String {
		switch self {
		case .body: return "Paragraph text throughout the book."
		case .heading: return "Chapter and section titles."
		case .caption: return "Available in body text as \\captionstyle."
		case .footnote: return "Footnote text at the bottom of the page."
		case .pageNumber: return "The running page number, if shown."
		}
	}
}

/// Every text type's style, edited together in "Edit Styles…". A style left
/// at its default (partial, with nothing overridden) changes nothing about
/// the compiled output — customizing font, size, or color is entirely opt-in.
struct TextStylesCatalog: Codable, Equatable {
	static let defaultBodySizePt = 11.0

	var body: TextStyle = .partial(PartialStyle())
	var heading: TextStyle = .partial(PartialStyle())
	var caption: TextStyle = .partial(PartialStyle())
	var footnote: TextStyle = .partial(PartialStyle())
	var pageNumber: TextStyle = .partial(PartialStyle())

	func style(for role: TextStyleRole) -> TextStyle {
		switch role {
		case .body: return body
		case .heading: return heading
		case .caption: return caption
		case .footnote: return footnote
		case .pageNumber: return pageNumber
		}
	}

	mutating func setStyle(_ style: TextStyle, for role: TextStyleRole) {
		switch role {
		case .body: body = style
		case .heading: heading = style
		case .caption: caption = style
		case .footnote: footnote = style
		case .pageNumber: pageNumber = style
		}
	}

	var usesSystemFont: Bool {
		TextStyleRole.allCases.contains { style(for: $0).usesSystemFont }
	}

	/// The point size body text resolves to — the reference every other
	/// role's relative size adjustment ("×1.5", "+2pt") is computed from.
	var resolvedBodySizePt: Double {
		switch body {
		case .full(let style): return style.sizePt
		case .partial(let style): return style.sizeAdjustment.resolved(otherwise: Self.defaultBodySizePt)
		}
	}

	private struct Resolved {
		var font: FontSelection?
		var sizePt: Double?
		var color: StyleColor?
	}

	private func resolve(_ style: TextStyle, bodySizePt: Double) -> Resolved {
		switch style {
		case .full(let full):
			return Resolved(font: full.font, sizePt: full.sizePt, color: full.color)
		case .partial(let partial):
			let sizePt: Double?
			if case .unchanged = partial.sizeAdjustment {
				sizePt = nil
			} else {
				sizePt = partial.sizeAdjustment.resolved(otherwise: bodySizePt)
			}
			return Resolved(font: partial.fontOverride, sizePt: sizePt, color: partial.color)
		}
	}

	/// Defines `\<role>style` for every role, and applies body's document-wide
	/// (main font/size/color). Re-styles chapter/section/subsection via
	/// titlesec only when headings are actually customized.
	var preamble: String {
		var lines: [String] = []
		var loadedPackages = Set<String>()
		let bodySize = resolvedBodySizePt

		func loadPackage(_ font: FontSelection?) {
			guard case .builtin(let choice) = font, let package = choice.package, loadedPackages.insert(package).inserted else {
				return
			}
			lines.append("\\usepackage{\(package)}")
		}

		func fontSelectCommand(_ font: FontSelection, macroNameForSystemFont: String) -> String {
			switch font {
			case .builtin(let choice):
				return choice.selectFontCommand
			case .system(let selection):
				let familyMacro = "\(macroNameForSystemFont)family"
				lines.append("\\newfontfamily\\\(familyMacro){\(selection.familyName)}\(selection.fontspecOptions)")
				return "\\\(familyMacro)"
			}
		}

		func ensureColorPackage() {
			if loadedPackages.insert("xcolor").inserted {
				lines.append("\\usepackage{xcolor}")
			}
		}

		// Body: applied document-wide.
		let bodyResolved = resolve(body, bodySizePt: bodySize)
		if let font = bodyResolved.font {
			loadPackage(font)
			switch font {
			case .builtin(let choice):
				if let code = choice.familyCode {
					lines.append("\\renewcommand{\\rmdefault}{\(code)}")
				}
			case .system(let selection):
				lines.append("\\setmainfont{\(selection.familyName)}\(selection.fontspecOptions)")
			}
		}
		if let sizePt = bodyResolved.sizePt {
			let leading = sizePt * 1.2
			lines.append(String(format: "\\renewcommand{\\normalsize}{\\fontsize{%.4g}{%.4g}\\selectfont}", sizePt, leading))
			lines.append(#"\normalsize"#)
		}
		if let color = bodyResolved.color {
			ensureColorPackage()
			lines.append("\\color\(color.latexColorArgument)")
		}

		// Heading, caption, footnote, page number: each becomes a standalone macro.
		for role in [TextStyleRole.heading, .caption, .footnote, .pageNumber] {
			let resolved = resolve(style(for: role), bodySizePt: bodySize)
			var parts: [String] = []
			if let font = resolved.font {
				loadPackage(font)
				parts.append(fontSelectCommand(font, macroNameForSystemFont: role.macroName))
			}
			if let sizePt = resolved.sizePt {
				let leading = sizePt * 1.2
				parts.append(String(format: "\\fontsize{%.4g}{%.4g}\\selectfont", sizePt, leading))
			}
			if let color = resolved.color {
				ensureColorPackage()
				parts.append("\\color\(color.latexColorArgument)")
			}
			let macroBody = parts.isEmpty ? #"\normalfont"# : parts.joined(separator: " ")
			lines.append("\\newcommand{\\\(role.macroName)}{\(macroBody)}")
		}

		// Re-style chapter/section/subsection only when headings actually differ from the default.
		if heading.isCustomized {
			let headingResolved = resolve(heading, bodySizePt: bodySize)
			let chapterSize = headingResolved.sizePt.map { String(format: "\\fontsize{%.4g}{%.4g}\\selectfont", $0, $0 * 1.2) } ?? #"\Huge"#
			let sectionSize = headingResolved.sizePt.map { String(format: "\\fontsize{%.4g}{%.4g}\\selectfont", $0, $0 * 1.2) } ?? #"\Large"#
			let subsectionSize = headingResolved.sizePt.map { String(format: "\\fontsize{%.4g}{%.4g}\\selectfont", $0, $0 * 1.2) } ?? #"\large"#
			lines.append(#"\usepackage{titlesec}"#)
			lines.append("\\titleformat{\\chapter}[display]{\\normalfont\\headingstyle}{\\chaptertitlename\\ \\thechapter}{20pt}{\(chapterSize)\\bfseries}")
			lines.append("\\titleformat{\\section}{\\normalfont\\headingstyle\\bfseries \(sectionSize)}{\\thesection}{1em}{}")
			lines.append("\\titleformat{\\subsection}{\\normalfont\\headingstyle\\bfseries \(subsectionSize)}{\\thesubsection}{1em}{}")
		}

		return lines.joined(separator: "\n")
	}
}
