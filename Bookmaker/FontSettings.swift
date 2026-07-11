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

/// A font installed on this Mac, chosen through the system font picker
/// rather than the curated pdflatex-safe list. Requires XeLaTeX/LuaLaTeX
/// (via fontspec) to actually typeset.
struct SystemFontSelection: Codable, Equatable {
	var postscriptName: String
	var familyName: String
	var displayName: String
	var isVariable: Bool
	/// OpenType axis tag -> chosen coordinate, e.g. "wght" -> 550. Only
	/// meaningful when `isVariable` is true.
	var axisValues: [String: Double] = [:]

	/// The fontspec `[Variations={...}]` clause, or empty for a static font.
	var fontspecOptions: String {
		guard isVariable, !axisValues.isEmpty else {
			return ""
		}
		let variations = axisValues
			.sorted { $0.key < $1.key }
			.map { tag, value in "\(tag)=\(Self.formatted(value))" }
			.joined(separator: ",")
		return "[Variations={\(variations)}]"
	}

	private static func formatted(_ value: Double) -> String {
		if value == value.rounded() {
			return String(Int(value))
		}
		return String(format: "%.2f", value)
	}
}

/// Either one of the built-in pdflatex-safe fonts, or a font picked from
/// everything installed on the system (which may be a variable font).
enum FontSelection: Codable, Equatable {
	case builtin(FontChoice)
	case system(SystemFontSelection)

	private enum CodingKeys: String, CodingKey {
		case kind, builtin, system
	}

	private enum Kind: String, Codable {
		case builtin, system
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		switch try container.decode(Kind.self, forKey: .kind) {
		case .builtin:
			self = .builtin(try container.decode(FontChoice.self, forKey: .builtin))
		case .system:
			self = .system(try container.decode(SystemFontSelection.self, forKey: .system))
		}
	}

	func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		switch self {
		case .builtin(let choice):
			try container.encode(Kind.builtin, forKey: .kind)
			try container.encode(choice, forKey: .builtin)
		case .system(let selection):
			try container.encode(Kind.system, forKey: .kind)
			try container.encode(selection, forKey: .system)
		}
	}
}

/// Default fonts for the three text roles Bookmaker distinguishes. Left at
/// `.builtin(.computerModern)` everywhere, this generates no preamble
/// changes at all, so choosing fonts is entirely opt-in.
struct FontSettings: Codable, Equatable {
	var bodyFont: FontSelection = .builtin(.computerModern)
	var headingFont: FontSelection = .builtin(.computerModern)
	var captionFont: FontSelection = .builtin(.computerModern)

	init() {}

	private enum CodingKeys: String, CodingKey {
		case bodyFont, headingFont, captionFont
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		bodyFont = Self.decodeSelection(container, .bodyFont) ?? .builtin(.computerModern)
		headingFont = Self.decodeSelection(container, .headingFont) ?? .builtin(.computerModern)
		captionFont = Self.decodeSelection(container, .captionFont) ?? .builtin(.computerModern)
	}

	/// Documents saved before `FontSelection` existed stored a bare `FontChoice`.
	/// (`try?` on an already-optional-returning call flattens to a single
	/// optional, so one `if let` unwraps both the error and the "absent" case.)
	private static func decodeSelection(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> FontSelection? {
		if let selection = try? container.decodeIfPresent(FontSelection.self, forKey: key) {
			return selection
		}
		if let legacy = try? container.decodeIfPresent(FontChoice.self, forKey: key) {
			return .builtin(legacy)
		}
		return nil
	}

	var usesSystemFont: Bool {
		for selection in [bodyFont, headingFont, captionFont] {
			if case .system = selection {
				return true
			}
		}
		return false
	}

	/// LaTeX preamble lines that apply these choices (fontenc/fontspec is
	/// handled once, document-wide, by `BookDocument`).
	var preamble: String {
		var lines: [String] = []
		var loadedPackages = Set<String>()

		switch bodyFont {
		case .builtin(let choice):
			if let package = choice.package, loadedPackages.insert(package).inserted {
				lines.append(#"\usepackage{\#(package)}"#)
			}
			if let bodyCode = choice.familyCode {
				lines.append(#"\renewcommand{\rmdefault}{\#(bodyCode)}"#)
			}
		case .system(let selection):
			lines.append(#"\setmainfont{\#(selection.familyName)}\#(selection.fontspecOptions)"#)
		}

		Self.appendFontFamilyMacro("headingfont", for: headingFont, loadedPackages: &loadedPackages, lines: &lines)
		Self.appendFontFamilyMacro("captionfont", for: captionFont, loadedPackages: &loadedPackages, lines: &lines)

		// Only re-style chapter/section headings when they should actually
		// look different from body text; otherwise leave book's own layout alone.
		if headingFont != bodyFont, Self.hasDistinctLook(headingFont) {
			lines.append(#"\usepackage{titlesec}"#)
			lines.append(#"\titleformat{\chapter}[display]{\normalfont\headingfont\bfseries}{\chaptertitlename\ \thechapter}{20pt}{\Huge}"#)
			lines.append(#"\titleformat{\section}{\normalfont\headingfont\Large\bfseries}{\thesection}{1em}{}"#)
			lines.append(#"\titleformat{\subsection}{\normalfont\headingfont\large\bfseries}{\thesubsection}{1em}{}"#)
		}

		return lines.joined(separator: "\n")
	}

	private static func hasDistinctLook(_ selection: FontSelection) -> Bool {
		switch selection {
		case .builtin(let choice): return choice.familyCode != nil
		case .system: return true
		}
	}

	/// Defines `\<macroName>` to switch to `selection`'s family, loading
	/// whatever package it needs first. Shared with `PageNumberSettings`.
	static func appendFontFamilyMacro(_ macroName: String, for selection: FontSelection, loadedPackages: inout Set<String>, lines: inout [String]) {
		switch selection {
		case .builtin(let choice):
			if let package = choice.package, loadedPackages.insert(package).inserted {
				lines.append("\\usepackage{\(package)}")
			}
			lines.append("\\newcommand{\\\(macroName)}{\(choice.selectFontCommand)}")
		case .system(let selection):
			let familyMacroName = "\(macroName)family"
			lines.append("\\newfontfamily\\\(familyMacroName){\(selection.familyName)}\(selection.fontspecOptions)")
			lines.append("\\newcommand{\\\(macroName)}{\\\(familyMacroName)}")
		}
	}
}
