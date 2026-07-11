import Foundation

enum FootnoteNumberingStyle: String, Codable, CaseIterable, Identifiable {
	case arabic = "1, 2, 3…"
	case roman = "i, ii, iii…"
	case alph = "a, b, c…"
	case symbol = "*, †, ‡…"

	var id: String { rawValue }

	var counterCommand: String {
		switch self {
		case .arabic: return #"\arabic{footnote}"#
		case .roman: return #"\roman{footnote}"#
		case .alph: return #"\alph{footnote}"#
		case .symbol: return #"\fnsymbol{footnote}"#
		}
	}
}

/// Footnote appearance. Left at the defaults, this generates no preamble
/// changes: footnotes look exactly like the book class's own, and
/// `\footnote[3]{...}`'s optional-number form keeps working, since the
/// font override hooks `\@makefntext` rather than redefining `\footnote` itself.
struct FootnoteSettings: Codable, Equatable {
	var numberingStyle: FootnoteNumberingStyle = .arabic
	var font: FontSelection = .builtin(.computerModern)
	/// Restart footnote numbering on every page rather than counting through the whole book.
	var resetsPerPage = false

	var usesSystemFont: Bool {
		if case .system = font {
			return true
		}
		return false
	}

	private var isDefaultFont: Bool {
		if case .builtin(.computerModern) = font {
			return true
		}
		return false
	}

	var preamble: String {
		var lines: [String] = []
		if resetsPerPage {
			lines.append(#"\usepackage[perpage]{footmisc}"#)
		}
		if numberingStyle != .arabic {
			lines.append("\\renewcommand{\\thefootnote}{\(numberingStyle.counterCommand)}")
		}
		if !isDefaultFont {
			var loadedPackages = Set<String>()
			FontSettings.appendFontFamilyMacro("footnotefont", for: font, loadedPackages: &loadedPackages, lines: &lines)
			lines.append(#"\makeatletter"#)
			lines.append(#"\let\bookmakerOldMakeFntext\@makefntext"#)
			lines.append(#"\renewcommand{\@makefntext}[1]{\footnotefont\bookmakerOldMakeFntext{#1}}"#)
			lines.append(#"\makeatother"#)
		}
		return lines.joined(separator: "\n")
	}
}
