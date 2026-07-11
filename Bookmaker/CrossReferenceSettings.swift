import Foundation

/// Finds `\label{...}` marks already typed in the document, so the
/// cross-reference picker and "Insert Reference Mark" can offer/generate names.
enum LabelScanner {
	static func labels(in text: String) -> [String] {
		var names: [String] = []
		var seen = Set<String>()
		guard let regex = try? NSRegularExpression(pattern: #"\\label\{([^}]+)\}"#) else {
			return names
		}
		let nsText = text as NSString
		regex.enumerateMatches(in: text, range: NSRange(location: 0, length: nsText.length)) { match, _, _ in
			guard let match = match, match.numberOfRanges > 1 else {
				return
			}
			let name = nsText.substring(with: match.range(at: 1))
			if seen.insert(name).inserted {
				names.append(name)
			}
		}
		return names
	}

	/// The next unused "markN" name, so a reference mark can be inserted with no naming prompt.
	static func nextMarkName(in text: String) -> String {
		let existing = Set(labels(in: text))
		var index = 1
		while existing.contains("mark\(index)") {
			index += 1
		}
		return "mark\(index)"
	}
}

/// How cross-references are phrased and introduced. Always loads varioref
/// when the document actually contains a `\vpageref`/`\vref` (decided by
/// `BookDocument`, which scans body text), so an untouched document gains
/// no new package dependency.
struct CrossReferenceSettings: Codable, Equatable {
	var introWord = "see"
	/// Adjacent-page references say "above"/"below" rather than varioref's
	/// stock "on the preceding/following page".
	var useAboveBelowPhrasing = true

	var preamble: String {
		var lines: [String] = []
		lines.append(#"\usepackage{varioref}"#)
		if useAboveBelowPhrasing {
			lines.append(#"\renewcommand{\reftextfaceafter}{below}"#)
			lines.append(#"\renewcommand{\reftextafter}{below}"#)
			lines.append(#"\renewcommand{\reftextfacebefore}{above}"#)
			lines.append(#"\renewcommand{\reftextbefore}{above}"#)
		}
		return lines.joined(separator: "\n")
	}

	/// The LaTeX snippet inserted at the cursor for a cross-reference to `label`.
	func referenceSnippet(to label: String) -> String {
		"\(introWord) \\vpageref{\(label)}"
	}
}
