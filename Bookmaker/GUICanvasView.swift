import SwiftUI
import AppKit

/// The unit page margins snap to while being dragged, per user preference.
enum MarginSnapUnit: String, CaseIterable, Identifiable {
	case millimeters = "mm"
	case points = "pt"
	var id: String { rawValue }

	func snapped(_ mm: Double) -> Double {
		switch self {
		case .millimeters:
			return mm.rounded()
		case .points:
			let pointsPerMM = 72.0 / 25.4
			return (mm * pointsPerMM).rounded() / pointsPerMM
		}
	}
}

/// A lightweight, page-shaped canvas: a first step toward a GUI/WYSIWYG
/// editing mode alongside the plain-text LaTeX editor. It mocks up the page
/// (or, in spread mode, a verso/recto pair) at true proportions (from
/// `PageSettings`), with zoom/pan matching standard macOS conventions, a
/// click-to-insert text tool, and guarded margin handles. It does not parse
/// or lay out `bodyText`; typed text is appended to the LaTeX source, the
/// same source the text editor and the PDF preview both work from.
struct GUICanvasView: View {
	@Binding var settings: PageSettings
	@Binding var bodyText: String
	@Binding var pageNumbers: PageNumberSettings
	let crossReferences: CrossReferenceSettings

	/// Which side of a spread a page mockup represents, since the margin
	/// closest to the spine (inner) sits on the opposite physical side
	/// depending on verso/recto.
	private enum PageSide: Equatable {
		case single, verso, recto

		var innerOnLeft: Bool {
			self != .verso
		}
	}

	private enum MarginKind: Equatable {
		case top, bottom, inner, outer
	}

	private enum InsertionKind: Equatable {
		case text, footnote
	}

	private static let pointsPerMM: CGFloat = 72.0 / 25.4
	private static let zoomRange: ClosedRange<CGFloat> = 0.25...4.0

	@State private var zoomScale: CGFloat = 1.0
	@State private var fitTrigger = 0

	@State private var isInsertingText = false
	@State private var insertionKind: InsertionKind = .text
	@State private var pendingInsertionPoint: CGPoint?
	@State private var pendingInsertionText = ""
	@State private var pendingInsertionSide: PageSide = .single

	@State private var marginsUnlocked = false
	@State private var activeDragMargin: (side: PageSide, kind: MarginKind)?
	@State private var dragStartValue: Double = 0
	@AppStorage("bookmaker.marginSnapUnit") private var marginSnapUnit: MarginSnapUnit = .millimeters

	@State private var showSpread = false

	@State private var showPageNumberSettings = false
	@State private var showCrossReferenceInsert = false

	private static let canvasPadding: CGFloat = 60

	var body: some View {
		VStack(spacing: 0) {
			toolbar
			Divider()
			CanvasScrollView(
				zoomScale: $zoomScale,
				hostedSize: CGSize(
					width: contentSizePoints.width * zoomScale + Self.canvasPadding * 2,
					height: contentSizePoints.height * zoomScale + Self.canvasPadding * 2
				),
				pageSize: pageSizePoints,
				zoomRange: Self.zoomRange,
				fitTrigger: fitTrigger
			) {
				canvas
					.padding(Self.canvasPadding)
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
				.help("Zoom out (⌘-)")
				.keyboardShortcut("-", modifiers: .command)
				Text("\(Int(zoomScale * 100))%")
					.font(.caption.monospacedDigit())
					.frame(width: 44)
				Button {
					zoomScale = min(Self.zoomRange.upperBound, zoomScale * 1.25)
				} label: {
					Image(systemName: "plus.magnifyingglass")
				}
				.help("Zoom in (⌘+)")
				.keyboardShortcut("+", modifiers: .command)
				Button("Fit") {
					fitTrigger += 1
				}
				.help("Fit the page in the window (⌘0)")
				.keyboardShortcut("0", modifiers: .command)
			}

			Divider().frame(height: 16)

			Toggle(isOn: $showSpread) {
				Label(showSpread ? "Spread" : "Single Page", systemImage: showSpread ? "book" : "doc")
			}
			.toggleStyle(.button)
			.help("Show the page alone, or as a verso/recto spread")

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

			Picker("Snap", selection: $marginSnapUnit) {
				ForEach(MarginSnapUnit.allCases) { unit in
					Text(unit.rawValue).tag(unit)
				}
			}
			.pickerStyle(.segmented)
			.labelsHidden()
			.frame(width: 80)
			.help("Unit margins snap to while dragging")

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

	/// The size the hosted content actually occupies (before the outer
	/// CanvasScrollView applies the padding around it), for sizing the
	/// scrollable area. A spread is two pages plus a small gutter gap.
	private var contentSizePoints: CGSize {
		let page = pageSizePoints
		guard showSpread else {
			return page
		}
		return CGSize(width: page.width * 2 + Self.spreadGutter, height: page.height)
	}

	private static let spreadGutter: CGFloat = 12

	private var canvas: some View {
		let size = pageSizePoints
		let content: AnyView
		if showSpread {
			content = AnyView(
				HStack(spacing: Self.spreadGutter) {
					pageView(side: .verso, size: size)
					pageView(side: .recto, size: size)
				}
			)
		} else {
			content = AnyView(pageView(side: .single, size: size))
		}
		return content
			.scaleEffect(zoomScale, anchor: .topLeading)
			.frame(width: contentSizePoints.width * zoomScale, height: contentSizePoints.height * zoomScale, alignment: .topLeading)
	}

	private func pageView(side: PageSide, size: CGSize) -> some View {
		ZStack(alignment: .topLeading) {
			Rectangle()
				.fill(Color.white)
				.frame(width: size.width, height: size.height)
				.overlay(Rectangle().stroke(Color.gray.opacity(0.5), lineWidth: 1))
				.shadow(radius: 3)

			marginOverlay(pageSize: size, side: side)

			if pageNumbers.isEnabled {
				pageNumberMarker(pageSize: size, side: side)
			}

			if isInsertingText {
				Color.black.opacity(0.001)
					.frame(width: size.width, height: size.height)
					.gesture(
						SpatialTapGesture()
							.onEnded { value in
								pendingInsertionSide = side
								pendingInsertionPoint = value.location
								pendingInsertionText = ""
							}
					)
			}

			if let point = pendingInsertionPoint, pendingInsertionSide == side {
				insertionPopover
					.position(x: min(max(point.x, 90), size.width - 90), y: min(max(point.y, 20), size.height - 20))
			}
		}
		.frame(width: size.width, height: size.height)
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
	private func pageNumberMarker(pageSize: CGSize, side: PageSide) -> some View {
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
		case .inner: x = side.innerOnLeft ? inner / 2 : pageSize.width - inner / 2
		case .center: x = pageSize.width / 2
		case .outer: x = side.innerOnLeft ? pageSize.width - outer / 2 : outer / 2
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

	private func marginOverlay(pageSize: CGSize, side: PageSide) -> some View {
		let top = settings.marginTop * Self.pointsPerMM
		let bottom = settings.marginBottom * Self.pointsPerMM
		let inner = settings.marginInner * Self.pointsPerMM
		let outer = settings.marginOuter * Self.pointsPerMM
		let leftMargin = side.innerOnLeft ? inner : outer
		let rightMargin = side.innerOnLeft ? outer : inner
		let textBlock = CGRect(
			x: leftMargin,
			y: top,
			width: max(0, pageSize.width - leftMargin - rightMargin),
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

			marginHandle(side, .top, label: "Top", value: settings.marginTop, at: CGPoint(x: pageSize.width / 2, y: top / 2))
			marginHandle(side, .bottom, label: "Bottom", value: settings.marginBottom, at: CGPoint(x: pageSize.width / 2, y: pageSize.height - bottom / 2))
			marginHandle(side, .inner, label: "Inner", value: settings.marginInner, at: CGPoint(x: side.innerOnLeft ? inner / 2 : pageSize.width - inner / 2, y: pageSize.height / 2))
			marginHandle(side, .outer, label: "Outer", value: settings.marginOuter, at: CGPoint(x: side.innerOnLeft ? pageSize.width - outer / 2 : outer / 2, y: pageSize.height / 2))
		}
	}

	/// The margin value formatted in whichever unit it currently snaps to.
	private func displayValue(_ mmValue: Double) -> String {
		switch marginSnapUnit {
		case .millimeters:
			return "\(Int(mmValue.rounded()))mm"
		case .points:
			let pointsPerMM = 72.0 / 25.4
			return "\(Int((mmValue * pointsPerMM).rounded()))pt"
		}
	}

	private func marginHandle(_ side: PageSide, _ kind: MarginKind, label: String, value: Double, at point: CGPoint) -> some View {
		Group {
			if marginsUnlocked {
				VStack(spacing: 2) {
					Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
						.font(.system(size: 10, weight: .bold))
					Text("\(label) \(displayValue(value))")
						.font(.caption2.bold())
				}
				.padding(4)
				.background(Color.accentColor)
				.foregroundColor(.white)
				.cornerRadius(4)
				.gesture(dragGesture(side, for: kind))
			} else {
				Text(displayValue(value))
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
		let snapped = marginSnapUnit.snapped(value)
		let clamped = max(2, snapped)
		switch kind {
		case .top: settings.marginTop = clamped
		case .bottom: settings.marginBottom = clamped
		case .inner: settings.marginInner = clamped
		case .outer: settings.marginOuter = clamped
		}
	}

	private func dragGesture(_ side: PageSide, for kind: MarginKind) -> some Gesture {
		DragGesture(minimumDistance: 2, coordinateSpace: .local)
			.onChanged { value in
				if activeDragMargin?.kind != kind || activeDragMargin?.side != side {
					activeDragMargin = (side, kind)
					dragStartValue = currentValue(for: kind)
				}
				// on a verso page, the inner/outer handles sit on the opposite
				// physical side, so dragging them moves the margin the other way
				let deltaPoints: CGFloat
				switch kind {
				case .top:
					deltaPoints = value.translation.height
				case .bottom:
					deltaPoints = -value.translation.height
				case .inner:
					deltaPoints = side.innerOnLeft ? value.translation.width : -value.translation.width
				case .outer:
					deltaPoints = side.innerOnLeft ? -value.translation.width : value.translation.width
				}
				// translation is reported in the view's own pre-scale coordinate
				// space, but that space is still inside the .scaleEffect(zoomScale)
				// applied in `canvas`, so it must be divided out here too
				let deltaMM = Double(deltaPoints) / (Self.pointsPerMM * zoomScale)
				setValue(dragStartValue + deltaMM, for: kind)
			}
			.onEnded { _ in
				activeDragMargin = nil
			}
	}
}
