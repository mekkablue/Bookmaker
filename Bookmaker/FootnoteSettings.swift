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

/// Footnote numbering. Font/size/color live in `TextStylesCatalog` (role
/// `.footnote`) alongside every other text type, edited via "Edit Styles…".
/// Left at the defaults, this generates no preamble changes: footnotes
/// look exactly like the book class's own, and `\footnote[3]{...}`'s
/// optional-number form keeps working, since the style hook wraps
/// `\@makefntext` rather than redefining `\footnote` itself.
struct FootnoteSettings: Codable, Equatable {
	var numberingStyle: FootnoteNumberingStyle = .arabic
	/// Restart footnote numbering on every page rather than counting through the whole book.
	var resetsPerPage = false

	/// `styleIsCustomized` is `TextStylesCatalog`'s `.footnote` role's
	/// `isCustomized`, passed in so this stays decoupled from the styles model.
	func preamble(styleIsCustomized: Bool) -> String {
		var lines: [String] = []
		if resetsPerPage {
			lines.append(#"\usepackage[perpage]{footmisc}"#)
		}
		if numberingStyle != .arabic {
			lines.append("\\renewcommand{\\thefootnote}{\(numberingStyle.counterCommand)}")
		}
		if styleIsCustomized {
			lines.append(#"\makeatletter"#)
			lines.append(#"\let\bookmakerOldMakeFntext\@makefntext"#)
			lines.append(#"\renewcommand{\@makefntext}[1]{\footnotestyle\bookmakerOldMakeFntext{#1}}"#)
			lines.append(#"\makeatother"#)
		}
		return lines.joined(separator: "\n")
	}
}
