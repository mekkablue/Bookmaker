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
/// an untouched document keeps the book class's own running heads.
struct PageNumberSettings: Codable, Equatable {
	var isEnabled = false
	var font: FontSelection = .builtin(.computerModern)
	var fontSize: Double = 10
	var vertical: PageNumberVerticalPosition = .bottom
	var horizontal: PageNumberHorizontalPosition = .outer
	/// Distance, in mm, from the page-number baseline to the margin line it's pinned to.
	var marginInset: Double = 8

	var usesSystemFont: Bool {
		guard isEnabled else {
			return false
		}
		if case .system = font {
			return true
		}
		return false
	}

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

	/// LaTeX preamble lines that place the page number using fancyhdr; empty when disabled.
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

		var loadedPackages = Set<String>()
		FontSettings.appendFontFamilyMacro("pagenumberfont", for: font, loadedPackages: &loadedPackages, lines: &lines)

		let sizePt = max(6, Int(fontSize.rounded()))
		let baselineSkip = max(sizePt, Int((fontSize * 1.2).rounded()))
		let numberText = #"\fontsize{\#(sizePt)}{\#(baselineSkip)}\selectfont\pagenumberfont\thepage"#

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
