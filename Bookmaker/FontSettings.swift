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

