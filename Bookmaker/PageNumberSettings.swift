import Foundation

enum PageNumberVerticalPosition: String, Codable, CaseIterable, Identifiable {
	case top = "Top"
	case bottom = "Bottom"
	var id: String { rawValue }
}

enum PageNumberHorizontalPosition: String, Codable, CaseIterable, Identifiable {
	case inner = "Inner"
	case center = "Center"
	case outer = "Outer"
	var id: String { rawValue }
}

/// Page numbers, positioned relative to the page margins so they're easy to
/// keep aligned with the text block as margins change. Off by default, so
/// an untouched document keeps the book class's own running heads. Font/
/// size/color live in `TextStylesCatalog` (role `.pageNumber`) alongside
/// every other text type, edited via "Edit Styles…".
struct PageNumberSettings: Codable, Equatable {
	var isEnabled = false
	var vertical: PageNumberVerticalPosition = .bottom
	var horizontal: PageNumberHorizontalPosition = .outer
	/// Distance, in mm, from the page-number baseline to the margin line it's pinned to.
	var marginInset: Double = 8

	/// Extra `geometry` package options that reserve space for the number
	/// at `marginInset` beyond the page margin.
	var geometryExtras: String {
		guard isEnabled else {
			return ""
		}
		switch vertical {
		case .bottom:
			return ", footskip=\(String(format: "%.5g", marginInset))mm"
		case .top:
			return ", headsep=\(String(format: "%.5g", marginInset))mm, headheight=14pt"
		}
	}

	/// LaTeX preamble lines that place the page number using fancyhdr
	/// (referencing `\pagenumberstyle`, always defined by `TextStylesCatalog`); empty when disabled.
	var preamble: String {
		guard isEnabled else {
			return ""
		}
		var lines: [String] = []
		lines.append(#"\usepackage{fancyhdr}"#)
		lines.append(#"\pagestyle{fancy}"#)
		lines.append(#"\fancyhf{}"#)
		lines.append(#"\renewcommand{\headrulewidth}{0pt}"#)
		lines.append(#"\renewcommand{\footrulewidth}{0pt}"#)

		let numberText = #"\pagenumberstyle\thepage"#

		let positionSpec: String
		switch horizontal {
		case .outer: positionSpec = "LE,RO"
		case .inner: positionSpec = "RE,LO"
		case .center: positionSpec = "C"
		}
		let command = vertical == .top ? "fancyhead" : "fancyfoot"
		lines.append("\\\(command)[\(positionSpec)]{\(numberText)}")
		return lines.joined(separator: "\n")
	}
}
