import SwiftUI
import AppKit

/// A scrollable, zoomable host for SwiftUI content that plain SwiftUI can't
/// provide on its own at this app's deployment target: real two-finger
/// trackpad panning (free from NSScrollView), Option+scrollwheel zoom, and
/// holding Space to drag-pan with a hand cursor. Zoom itself stays driven by
/// the caller's own `zoomScale` (applied as a SwiftUI `.scaleEffect` to
/// `content` by the caller, before it's ever passed in here), not
/// NSScrollView's built-in magnification, so the content's own gesture math
/// (e.g. margin-handle dragging) keeps working unchanged.
struct CanvasScrollView<Content: View>: NSViewRepresentable {
	@Binding var zoomScale: CGFloat
	/// The exact size `content` will render itself at (already scaled and
	/// padded by the caller) — this is what the NSHostingView's frame is set
	/// to, so it must match `content`'s actual size or the content clips.
	var hostedSize: CGSize
	/// The unscaled page size, used only to compute "fit to window".
	var pageSize: CGSize
	var zoomRange: ClosedRange<CGFloat>
	/// Incremented from outside to request a "fit to window" pass.
	var fitTrigger: Int
	@ViewBuilder var content: () -> Content

	func makeCoordinator() -> Coordinator {
		Coordinator(zoomScale: $zoomScale, zoomRange: zoomRange)
	}

	func makeNSView(context: Context) -> NSScrollView {
		let scrollView = NSScrollView()
		scrollView.hasVerticalScroller = true
		scrollView.hasHorizontalScroller = true
		scrollView.borderType = .noBorder
		scrollView.drawsBackground = false

		let container = FlippedContainerView()
		let hosting = NSHostingView(rootView: content())
		container.addSubview(hosting)

		let catcher = SpacePanCatcherView()
		catcher.panHandler = { [weak coordinator = context.coordinator] delta in
			coordinator?.pan(by: delta)
		}
		container.addSubview(catcher)

		context.coordinator.scrollView = scrollView
		context.coordinator.containerView = container
		context.coordinator.hostingView = hosting
		context.coordinator.catcherView = catcher
		context.coordinator.installMonitor()

		scrollView.documentView = container
		return scrollView
	}

	func updateNSView(_ scrollView: NSScrollView, context: Context) {
		context.coordinator.zoomScale = $zoomScale
		context.coordinator.zoomRange = zoomRange
		(context.coordinator.hostingView as? NSHostingView<Content>)?.rootView = content()

		context.coordinator.updateSize(hostedSize)

		if context.coordinator.lastFitTrigger != fitTrigger {
			context.coordinator.lastFitTrigger = fitTrigger
			context.coordinator.fit(pageSize: pageSize)
		}
	}

	final class Coordinator {
		var zoomScale: Binding<CGFloat>
		var zoomRange: ClosedRange<CGFloat>
		weak var scrollView: NSScrollView?
		weak var containerView: NSView?
		weak var hostingView: NSView?
		weak var catcherView: SpacePanCatcherView?
		var lastFitTrigger = 0
		private var monitor: Any?

		init(zoomScale: Binding<CGFloat>, zoomRange: ClosedRange<CGFloat>) {
			self.zoomScale = zoomScale
			self.zoomRange = zoomRange
		}

		func updateSize(_ size: CGSize) {
			guard size.width > 0, size.height > 0 else {
				return
			}
			let frame = CGRect(origin: .zero, size: size)
			if hostingView?.frame.size != size {
				hostingView?.frame = frame
			}
			if containerView?.frame.size != size {
				containerView?.frame = frame
			}
			if catcherView?.frame.size != size {
				catcherView?.frame = frame
			}
		}

		func pan(by delta: CGSize) {
			guard let scrollView else {
				return
			}
			let clipView = scrollView.contentView
			var origin = clipView.bounds.origin
			origin.x -= delta.width
			origin.y += delta.height
			clipView.scroll(to: origin)
			scrollView.reflectScrolledClipView(clipView)
		}

		func zoom(by factor: CGFloat) {
			let newScale = min(max(zoomScale.wrappedValue * factor, zoomRange.lowerBound), zoomRange.upperBound)
			zoomScale.wrappedValue = newScale
		}

		/// Picks the largest zoom that fits the whole page in the visible viewport.
		func fit(pageSize: CGSize) {
			guard let scrollView, pageSize.width > 0, pageSize.height > 0 else {
				return
			}
			let viewport = scrollView.contentView.bounds.size
			guard viewport.width > 20, viewport.height > 20 else {
				return
			}
			let horizontalScale = viewport.width / pageSize.width
			let verticalScale = viewport.height / pageSize.height
			let fitted = min(horizontalScale, verticalScale) * 0.96 // small margin so edges aren't flush against the scrollers
			let newScale = min(max(fitted, zoomRange.lowerBound), zoomRange.upperBound)
			// deferred: mutating the zoomScale binding synchronously here, while
			// still inside SwiftUI's updateNSView, is undefined behavior
			DispatchQueue.main.async { [weak scrollView, zoomScale] in
				zoomScale.wrappedValue = newScale
				guard let scrollView else {
					return
				}
				scrollView.contentView.scroll(to: .zero)
				scrollView.reflectScrolledClipView(scrollView.contentView)
			}
		}

		func installMonitor() {
			guard monitor == nil else {
				return
			}
			monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .scrollWheel]) { [weak self] event in
				self?.handle(event) ?? event
			}
		}

		private func handle(_ event: NSEvent) -> NSEvent? {
			guard let window = scrollView?.window, event.window === window else {
				return event
			}
			switch event.type {
			case .scrollWheel:
				guard event.modifierFlags.contains(.option) else {
					return event
				}
				guard isMouseOverScrollView(event) else {
					return event
				}
				let factor = 1 + (event.scrollingDeltaY * 0.01)
				zoom(by: factor)
				return nil
			case .keyDown:
				guard event.keyCode == 49, !(window.firstResponder is NSTextView) else {
					return event
				}
				if !event.isARepeat {
					catcherView?.isSpaceDown = true
					NSCursor.openHand.set()
				}
				return nil
			case .keyUp:
				guard event.keyCode == 49 else {
					return event
				}
				catcherView?.isSpaceDown = false
				NSCursor.arrow.set()
				return event
			default:
				return event
			}
		}

		private func isMouseOverScrollView(_ event: NSEvent) -> Bool {
			guard let scrollView, let superview = scrollView.superview else {
				return false
			}
			let locationInSuperview = superview.convert(event.locationInWindow, from: nil)
			return scrollView.frame.contains(locationInSuperview)
		}

		deinit {
			if let monitor {
				NSEvent.removeMonitor(monitor)
			}
		}
	}
}

/// The scroll view's document view. Flipped to match SwiftUI's own
/// top-left-origin, downward-growing coordinate convention.
private final class FlippedContainerView: NSView {
	override var isFlipped: Bool { true }
}

/// Sits on top of the hosted SwiftUI content. While Space isn't held it
/// declines every hit test so clicks fall through to the content underneath;
/// while Space is held it captures drags and pans the enclosing scroll view.
final class SpacePanCatcherView: NSView {
	var isSpaceDown = false
	var panHandler: ((CGSize) -> Void)?
	private var lastDragLocation: NSPoint?

	override var isFlipped: Bool { true }

	override func hitTest(_ point: NSPoint) -> NSView? {
		isSpaceDown ? self : nil
	}

	override func mouseDown(with event: NSEvent) {
		lastDragLocation = event.locationInWindow
		NSCursor.closedHand.set()
	}

	override func mouseDragged(with event: NSEvent) {
		guard let last = lastDragLocation else {
			return
		}
		let current = event.locationInWindow
		let delta = CGSize(width: current.x - last.x, height: current.y - last.y)
		lastDragLocation = current
		panHandler?(delta)
	}

	override func mouseUp(with event: NSEvent) {
		lastDragLocation = nil
		NSCursor.openHand.set()
	}
}
