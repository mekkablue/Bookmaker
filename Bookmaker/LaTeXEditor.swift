import SwiftUI
import AppKit

/// Plain-text LaTeX editor: an NSTextView with all smart substitutions off
/// (smart quotes would corrupt LaTeX source) and two kinds of autocompletion.
/// Typing a backslash opens a popup of LaTeX commands automatically, narrowing
/// as you type. Pressing Escape while inside any other word opens a popup of
/// completions drawn from every word already typed elsewhere in the document,
/// so recurring names and terms complete without a fixed dictionary.
struct LaTeXEditor: NSViewRepresentable {
	@Binding var text: String

	func makeCoordinator() -> Coordinator {
		Coordinator(self)
	}

	func makeNSView(context: Context) -> NSScrollView {
		let textView = LaTeXTextView()
		textView.delegate = context.coordinator
		textView.isRichText = false
		textView.allowsUndo = true
		textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
		textView.isAutomaticQuoteSubstitutionEnabled = false
		textView.isAutomaticDashSubstitutionEnabled = false
		textView.isAutomaticTextReplacementEnabled = false
		textView.isAutomaticSpellingCorrectionEnabled = false
		textView.isContinuousSpellCheckingEnabled = false
		textView.textContainerInset = NSSize(width: 5, height: 8)

		textView.minSize = .zero
		textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
		textView.isVerticallyResizable = true
		textView.isHorizontallyResizable = false
		textView.autoresizingMask = [.width]
		textView.textContainer?.widthTracksTextView = true
		textView.string = text

		let scrollView = NSScrollView()
		scrollView.documentView = textView
		scrollView.hasVerticalScroller = true
		return scrollView
	}

	func updateNSView(_ scrollView: NSScrollView, context: Context) {
		context.coordinator.parent = self
		guard let textView = scrollView.documentView as? LaTeXTextView else {
			return
		}
		if textView.string != text {
			// external change (switching Body/Template, Reset to Default): replace wholesale
			textView.string = text
			textView.undoManager?.removeAllActions()
		}
	}

	final class Coordinator: NSObject, NSTextViewDelegate {
		var parent: LaTeXEditor

		init(_ parent: LaTeXEditor) {
			self.parent = parent
		}

		func textDidChange(_ notification: Notification) {
			guard let textView = notification.object as? LaTeXTextView else {
				return
			}
			parent.text = textView.string
			textView.completeIfInCommandToken()
		}

		func textView(_ textView: NSTextView, completions words: [String], forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>?) -> [String] {
			let partialToken = (textView.string as NSString).substring(with: charRange)
			if partialToken.hasPrefix("\\") {
				index?.pointee = -1  // no preselection, so Return while typing does not insert by surprise
				return LaTeXCommands.all.filter { $0.hasPrefix(partialToken) }
			}
			guard !partialToken.isEmpty else {
				return words
			}
			index?.pointee = -1
			return Self.wordsTyped(in: textView.string, matching: partialToken)
		}

		/// Every distinct word already typed in the document that starts with
		/// `prefix` (case-insensitively), excluding the word being typed itself.
		private static func wordsTyped(in text: String, matching prefix: String) -> [String] {
			var found = Set<String>()
			text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.byWords, .localized]) { substring, _, _, _ in
				guard let word = substring, word.count > 1 else {
					return
				}
				found.insert(word)
			}
			let lowerPrefix = prefix.lowercased()
			return found
				.filter { $0.lowercased().hasPrefix(lowerPrefix) && $0.caseInsensitiveCompare(prefix) != .orderedSame }
				.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
		}
	}
}

final class LaTeXTextView: NSTextView {
	private var isCompleting = false

	/// Extend the system's partial-word range to include the backslash that
	/// starts a LaTeX command, so completions can match against "\chap".
	override var rangeForUserCompletion: NSRange {
		let range = super.rangeForUserCompletion
		guard range.location != NSNotFound, range.location > 0 else {
			return range
		}
		let backslash: unichar = 0x5C
		if (string as NSString).character(at: range.location - 1) == backslash {
			return NSRange(location: range.location - 1, length: range.length + 1)
		}
		return range
	}

	/// If the insertion point sits at the end of a backslash command token,
	/// open the completion popup (only when there is something to offer).
	func completeIfInCommandToken() {
		guard !isCompleting, window != nil else {
			return
		}
		let caret = selectedRange().location
		let text = string as NSString
		guard caret != NSNotFound, caret > 0, caret <= text.length else {
			return
		}
		let textBeforeCaret = text.substring(to: caret)
		guard let tokenRange = textBeforeCaret.range(of: #"\\[A-Za-z]*$"#, options: .regularExpression) else {
			return
		}
		let partialToken = String(textBeforeCaret[tokenRange])
		guard LaTeXCommands.hasMatch(forPartialToken: partialToken) else {
			return
		}
		isCompleting = true
		complete(nil)
		isCompleting = false
	}

	override func insertCompletion(_ word: String, forPartialWordRange charRange: NSRange, movement: Int, isFinal flag: Bool) {
		// guard against re-triggering the popup from the text change this causes
		isCompleting = true
		super.insertCompletion(word, forPartialWordRange: charRange, movement: movement, isFinal: flag)
		isCompleting = false
	}
}
