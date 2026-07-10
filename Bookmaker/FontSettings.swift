import Foundation

/// A curated set of fonts that work with plain pdflatex (no fontspec/XeLaTeX
/// required): classic PSNFSS packages built on the 35 standard PostScript
/// fonts, plus Latin Modern. Each ships as its own small, dependency-free
/// package, so picking one never requires more than pdflatex already has.
enum FontChoice: String, CaseIterable, Identifiable, Codable {
	case computerModern = "Computer Modern (Default)"
	case latinModern = "Latin Modern"
	case times = "Times"
	case palatino = "Palatino"
	case bookman = "Bookman"
	case helvetica = "Helvetica"
	case avantGarde = "Avant Garde"
	case courier = "Courier"

	var id: String { rawValue }

	/// The LaTeX package that makes this family's metrics available, if any.
	var package: String? {
		switch self {
		case .computerModern: return nil
		case .latinModern: return "lmodern"
		case .times: return "times"
		case .palatino: return "palatino"
		case .bookman: return "bookman"
		case .helvetica: return "helvet"
		case .avantGarde: return "avant"
		case .courier: return "courier"
		}
	}

	/// The NFSS family code used with \fontfamily{}, if this isn't the engine default.
	var familyCode: String? {
		switch self {
		case .computerModern: return nil
		case .latinModern: return "lmr"
		case .times: return "ptm"
		case .palatino: return "ppl"
		case .bookman: return "pbk"
		case .helvetica: return "phv"
		case .avantGarde: return "pag"
		case .courier: return "pcr"
		}
	}

	/// The LaTeX snippet that switches to this family wherever it is placed.
	var selectFontCommand: String {
		guard let familyCode = familyCode else {
			return #"\normalfont"#
		}
		return #"\fontfamily{\#(familyCode)}\selectfont"#
	}
}

/// Default fonts for the three text roles Bookmaker distinguishes. Left at
/// `.computerModern` everywhere, this generates no preamble changes at all,
/// so choosing fonts is entirely opt-in and never perturbs an existing book.
struct FontSettings: Codable, Equatable {
	var bodyFont: FontChoice = .computerModern
	var headingFont: FontChoice = .computerModern
	var captionFont: FontChoice = .computerModern

	/// LaTeX preamble lines that apply these choices.
	var preamble: String {
		var lines: [String] = []
		var loadedPackages = Set<String>()

		func loadPackage(_ choice: FontChoice) {
			if let package = choice.package, loadedPackages.insert(package).inserted {
				lines.append(#"\usepackage{\#(package)}"#)
			}
		}

		loadPackage(bodyFont)
		if let bodyCode = bodyFont.familyCode {
			lines.append(#"\renewcommand{\rmdefault}{\#(bodyCode)}"#)
		}

		loadPackage(headingFont)
		lines.append(#"\newcommand{\headingfont}{\#(headingFont.selectFontCommand)}"#)

		loadPackage(captionFont)
		lines.append(#"\newcommand{\captionfont}{\#(captionFont.selectFontCommand)}"#)

		// Only re-style chapter/section headings when they should actually
		// look different from body text; otherwise leave book's own layout alone.
		if headingFont != bodyFont, headingFont.familyCode != nil {
			lines.append(#"\usepackage{titlesec}"#)
			lines.append(#"\titleformat{\chapter}[display]{\normalfont\headingfont\bfseries}{\chaptertitlename\ \thechapter}{20pt}{\Huge}"#)
			lines.append(#"\titleformat{\section}{\normalfont\headingfont\Large\bfseries}{\thesection}{1em}{}"#)
			lines.append(#"\titleformat{\subsection}{\normalfont\headingfont\large\bfseries}{\thesubsection}{1em}{}"#)
		}

		return lines.joined(separator: "\n")
	}
}
