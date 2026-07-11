import SwiftUI
import AppKit

/// A lightweight, page-shaped canvas: a first step toward a GUI/WYSIWYG
/// editing mode alongside the plain-text LaTeX editor. It mocks up the page
/// at true proportions (from `PageSettings`) and offers zoom, pan, a
/// click-to-insert text tool, and guarded margin handles. It does not parse
/// or lay out `bodyText`; typed text is appended to the LaTeX source, the
/// same source the text editor and the PDF preview both work from.
struct GUICanvasView: View {
	@Binding var settings: PageSettings
	@Binding var bodyText: String
	@Binding var pageNumbers: PageNumberSettings
	let crossReferences: CrossReferenceSettings

	private enum MarginKind: Equatable {
		case top, bottom, inner, outer
	}

	private enum InsertionKind: Equatable {
		case text, footnote
	}

	private static let pointsPerMM: CGFloat = 72.0 / 25.4
	private static let zoomRange: ClosedRange<CGFloat> = 0.25...4.0

	@State private var zoomScale: CGFloat = 1.0
	@GestureState private var magnifyBy: CGFloat = 1.0

	@State private var isInsertingText = false
	@State private var insertionKind: InsertionKind = .text
	@State private var pendingInsertionPoint: CGPoint?
	@State private var pendingInsertionText = ""

	@State private var marginsUnlocked = false
	@State private var activeDragMargin: MarginKind?
	@State private var dragStartValue: Double = 0

	@State private var showPageNumberSettings = false
	@State private var showCrossReferenceInsert = false

	var body: some View {
		VStack(spacing: 0) {
			toolbar
			Divider()
			ScrollView([.horizontal, .vertical]) {
				canvas
					.padding(60)
			}
			.background(Color(nsColor: .underPageBackgroundColor))
		}
	}

	// MARK: - Toolbar

	private var toolbar: some View {
		HStack(spacing: 14) {
			HStack(spacing: 4) {
				Button {
					zoomScale = max(Self.zoomRange.lowerBound, zoomScale / 1.25)
				} label: {
					Image(systemName: "minus.magnifyingglass")
				}
				.help("Zoom out")
				Text("\(Int(zoomScale * 100))%")
					.font(.caption.monospacedDigit())
					.frame(width: 44)
				Button {
					zoomScale = min(Self.zoomRange.upperBound, zoomScale * 1.25)
				} label: {
					Image(systemName: "plus.magnifyingglass")
				}
				.help("Zoom in")
				Button("Reset") {
					zoomScale = 1.0
				}
				.help("Reset zoom to 100%")
			}

			Divider().frame(height: 16)

			Toggle(isOn: Binding(
				get: { isInsertingText && insertionKind == .text },
				set: { active in
					isInsertingText = active
					if active { insertionKind = .text }
				}
			)) {
				Label("Insert Text", systemImage: "text.insert")
			}
			.toggleStyle(.button)
			.help("Click the page to insert a new paragraph of text")

			Toggle(isOn: Binding(
				get: { isInsertingText && insertionKind == .footnote },
				set: { active in
					isInsertingText = active
					if active { insertionKind = .footnote }
				}
			)) {
				Label("Insert Footnote", systemImage: "textformat.subscript")
			}
			.toggleStyle(.button)
			.help("Click the page to insert a footnote")

			Button {
				let name = LabelScanner.nextMarkName(in: bodyText)
				appendToBody("\\label{\(name)}")
			} label: {
				Label("Insert Reference Mark", systemImage: "mappin")
			}
			.help("Add a mark elsewhere in the text can point to")

			Button {
				showCrossReferenceInsert = true
			} label: {
				Label("Insert Cross-Reference", systemImage: "arrow.turn.up.right")
			}
			.help("Insert a \u{201c}see above/below/on page N\u{201d} reference to a mark")
			.popover(isPresented: $showCrossReferenceInsert) {
				CrossReferenceInsertView(bodyText: bodyText, introWord: crossReferences.introWord) { label in
					appendToBody(crossReferences.referenceSnippet(to: label))
				}
			}

			Divider().frame(height: 16)

			Toggle(isOn: $marginsUnlocked) {
				Label(marginsUnlocked ? "Margins Unlocked" : "Margins Locked", systemImage: marginsUnlocked ? "lock.open" : "lock")
			}
			.toggleStyle(.button)
			.tint(marginsUnlocked ? .orange : nil)
			.help("Unlock to drag the margin guides; locked margins can't be moved by accident")

			Divider().frame(height: 16)

			Button {
				showPageNumberSettings = true
			} label: {
				Label("Page Numbers", systemImage: "number")
			}
			.help("Show and position page numbers")
			.popover(isPresented: $showPageNumberSettings) {
				PageNumberSettingsView(pageNumbers: $pageNumbers)
			}

			Spacer()
		}
		.padding(8)
	}

	// MARK: - Canvas

	private var pageSizePoints: CGSize {
		CGSize(width: settings.paperWidth * Self.pointsPerMM, height: settings.paperHeight * Self.pointsPerMM)
	}

	private var effectiveScale: CGFloat {
		zoomScale * magnifyBy
	}

	private var canvas: some View {
		let size = pageSizePoints
		return ZStack(alignment: .topLeading) {
			Rectangle()
				.fill(Color.white)
				.frame(width: size.width, height: size.height)
				.overlay(Rectangle().stroke(Color.gray.opacity(0.5), lineWidth: 1))
				.shadow(radius: 3)

			marginOverlay(pageSize: size)

			if pageNumbers.isEnabled {
				pageNumberMarker(pageSize: size)
			}

			if isInsertingText {
				Color.black.opacity(0.001)
					.frame(width: size.width, height: size.height)
					.gesture(
						SpatialTapGesture()
							.onEnded { value in
								pendingInsertionPoint = value.location
								pendingInsertionText = ""
							}
					)
			}

			if let point = pendingInsertionPoint {
				insertionPopover
					.position(x: min(max(point.x, 90), size.width - 90), y: min(max(point.y, 20), size.height - 20))
			}
		}
		.frame(width: size.width, height: size.height)
		.scaleEffect(effectiveScale, anchor: .topLeading)
		.frame(width: size.width * effectiveScale, height: size.height * effectiveScale)
		.gesture(
			MagnificationGesture()
				.updating($magnifyBy) { value, state, _ in state = value }
				.onEnded { value in
					zoomScale = min(max(zoomScale * value, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
				}
		)
	}

	// MARK: - Text insertion

	private var insertionPopover: some View {
		VStack(alignment: .leading, spacing: 6) {
			TextField(insertionKind == .footnote ? "Footnote text…" : "New paragraph…", text: $pendingInsertionText, onCommit: commitInsertion)
				.textFieldStyle(.roundedBorder)
				.frame(width: 180)
			HStack {
				Button("Cancel") {
					pendingInsertionPoint = nil
					pendingInsertionText = ""
				}
				.controlSize(.small)
				Spacer()
				Button("Insert") {
					commitInsertion()
				}
				.controlSize(.small)
				.disabled(pendingInsertionText.isEmpty)
			}
		}
		.padding(8)
		.background(.regularMaterial)
		.cornerRadius(6)
		.shadow(radius: 4)
		.frame(width: 196)
	}

	private func commitInsertion() {
		guard !pendingInsertionText.isEmpty else {
			pendingInsertionPoint = nil
			return
		}
		let content = insertionKind == .footnote ? "\\footnote{\(pendingInsertionText)}" : pendingInsertionText
		appendToBody(content)
		pendingInsertionPoint = nil
		pendingInsertionText = ""
	}

	/// bodyText has no live layout, so every canvas insertion tool appends
	/// to the end rather than trying to map a click point to a position in
	/// the LaTeX source.
	private func appendToBody(_ text: String) {
		let separator = bodyText.isEmpty || bodyText.hasSuffix("\n\n") ? "" : "\n\n"
		bodyText += separator + text
	}

	// MARK: - Page numbers

	/// Positioned relative to the margin lines already drawn, so the number
	/// visibly stays pinned to whichever margin it's aligned with.
	private func pageNumberMarker(pageSize: CGSize) -> some View {
		let top = settings.marginTop * Self.pointsPerMM
		let bottom = settings.marginBottom * Self.pointsPerMM
		let inner = settings.marginInner * Self.pointsPerMM
		let outer = settings.marginOuter * Self.pointsPerMM
		let insetPoints = pageNumbers.marginInset * Self.pointsPerMM

		let y: CGFloat
		switch pageNumbers.vertical {
		case .top: y = max(6, top - insetPoints)
		case .bottom: y = min(pageSize.height - 6, pageSize.height - bottom + insetPoints)
		}
		let x: CGFloat
		switch pageNumbers.horizontal {
		case .inner: x = inner / 2
		case .center: x = pageSize.width / 2
		case .outer: x = pageSize.width - outer / 2
		}

		return Text("1")
			.font(.system(size: 9, weight: .medium))
			.foregroundColor(.secondary)
			.padding(3)
			.background(Color.accentColor.opacity(0.15))
			.cornerRadius(3)
			.position(x: x, y: y)
	}

	// MARK: - Margins

	private func marginOverlay(pageSize: CGSize) -> some View {
		let top = settings.marginTop * Self.pointsPerMM
		let bottom = settings.marginBottom * Self.pointsPerMM
		let inner = settings.marginInner * Self.pointsPerMM
		let outer = settings.marginOuter * Self.pointsPerMM
		let textBlock = CGRect(
			x: inner,
			y: top,
			width: max(0, pageSize.width - inner - outer),
			height: max(0, pageSize.height - top - bottom)
		)

		return ZStack(alignment: .topLeading) {
			Rectangle()
				.strokeBorder(
					marginsUnlocked ? Color.accentColor : Color.gray.opacity(0.35),
					style: StrokeStyle(lineWidth: marginsUnlocked ? 1.5 : 0.75, dash: [4, 3])
				)
				.frame(width: textBlock.width, height: textBlock.height)
				.offset(x: textBlock.minX, y: textBlock.minY)

			marginHandle(.top, label: "Top", value: settings.marginTop, at: CGPoint(x: pageSize.width / 2, y: top / 2))
			marginHandle(.bottom, label: "Bottom", value: settings.marginBottom, at: CGPoint(x: pageSize.width / 2, y: pageSize.height - bottom / 2))
			marginHandle(.inner, label: "Inner", value: settings.marginInner, at: CGPoint(x: inner / 2, y: pageSize.height / 2))
			marginHandle(.outer, label: "Outer", value: settings.marginOuter, at: CGPoint(x: pageSize.width - outer / 2, y: pageSize.height / 2))
		}
	}

	private func marginHandle(_ kind: MarginKind, label: String, value: Double, at point: CGPoint) -> some View {
		Group {
			if marginsUnlocked {
				VStack(spacing: 2) {
					Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
						.font(.system(size: 10, weight: .bold))
					Text("\(label) \(Int(value))mm")
						.font(.caption2.bold())
				}
				.padding(4)
				.background(Color.accentColor)
				.foregroundColor(.white)
				.cornerRadius(4)
				.gesture(dragGesture(for: kind))
			} else {
				Text("\(Int(value))mm")
					.font(.system(size: 8))
					.foregroundColor(.gray.opacity(0.6))
					.padding(2)
			}
		}
		.position(point)
	}

	private func currentValue(for kind: MarginKind) -> Double {
		switch kind {
		case .top: return settings.marginTop
		case .bottom: return settings.marginBottom
		case .inner: return settings.marginInner
		case .outer: return settings.marginOuter
		}
	}

	private func setValue(_ value: Double, for kind: MarginKind) {
		let clamped = max(2, value)
		switch kind {
		case .top: settings.marginTop = clamped
		case .bottom: settings.marginBottom = clamped
		case .inner: settings.marginInner = clamped
		case .outer: settings.marginOuter = clamped
		}
	}

	private func dragGesture(for kind: MarginKind) -> some Gesture {
		DragGesture(minimumDistance: 2, coordinateSpace: .local)
			.onChanged { value in
				if activeDragMargin != kind {
					activeDragMargin = kind
					dragStartValue = currentValue(for: kind)
				}
				let deltaPoints: CGFloat
				switch kind {
				case .top: deltaPoints = value.translation.height
				case .bottom: deltaPoints = -value.translation.height
				case .inner: deltaPoints = value.translation.width
				case .outer: deltaPoints = -value.translation.width
				}
				let deltaMM = Double(deltaPoints) / (Self.pointsPerMM * effectiveScale)
				setValue(dragStartValue + deltaMM, for: kind)
			}
			.onEnded { _ in
				activeDragMargin = nil
			}
	}
}
