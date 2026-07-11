import SwiftUI
import AppKit

/// One slider per STAT axis of a variable font, instead of one big dropdown
/// listing every named instance. Continuous axes (present in the file's own
/// `fvar` table) snap to each STAT stop by default; hold Shift while
/// dragging to move freely between stops. Axes known only from STAT —
/// typically an italic axis implemented as a sibling file — offer just
/// their discrete stops, since this file can't interpolate them.
struct VariableFontAxesView: View {
	let axes: [VariableFontAxis]
	@Binding var values: [String: Double]

	@State private var panelWidth: CGFloat = 420
	private let minPanelWidth: CGFloat = 320
	private let maxPanelWidth: CGFloat = 900

	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			ForEach(axes) { axis in
				axisRow(axis)
			}
			resizeHandle
		}
		.frame(width: panelWidth)
		.onAppear {
			for axis in axes where values[axis.tag] == nil {
				values[axis.tag] = Self.defaultValue(for: axis)
			}
		}
	}

	private func axisRow(_ axis: VariableFontAxis) -> some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack {
				Text(axis.name)
					.font(.caption.bold())
				if !axis.isContinuousInThisFile {
					Text("(discrete)")
						.font(.caption2)
						.foregroundColor(.secondary)
				}
				Spacer()
				Text(currentStopLabel(axis))
					.font(.caption)
					.foregroundColor(.secondary)
			}
			if axis.isContinuousInThisFile {
				// snaps to STAT stops if any exist; otherwise a plain fvar-range slider
				ContinuousAxisSlider(axis: axis, value: binding(for: axis))
					.frame(width: panelWidth - 24)
			} else {
				Picker("", selection: binding(for: axis)) {
					ForEach(axis.stops) { stop in
						Text(stop.name).tag(stop.value)
					}
				}
				.pickerStyle(.segmented)
				.labelsHidden()
			}
		}
	}

	private var resizeHandle: some View {
		HStack {
			Spacer()
			Image(systemName: "arrow.left.and.right")
				.foregroundColor(.secondary)
				.padding(4)
				.contentShape(Rectangle())
				.gesture(
					DragGesture()
						.onChanged { value in
							panelWidth = min(maxPanelWidth, max(minPanelWidth, panelWidth + value.translation.width))
						}
				)
				.help("Drag to widen the sliders for finer control")
		}
	}

	private func binding(for axis: VariableFontAxis) -> Binding<Double> {
		Binding(
			get: { values[axis.tag] ?? Self.defaultValue(for: axis) },
			set: { values[axis.tag] = $0 }
		)
	}

	private func currentStopLabel(_ axis: VariableFontAxis) -> String {
		let value = values[axis.tag] ?? Self.defaultValue(for: axis)
		if let stop = axis.stops.first(where: { abs($0.value - value) < 0.01 }) {
			return stop.name
		}
		return String(format: "%.0f", value)
	}

	/// The first elidable STAT stop, or the stop closest to the fvar
	/// default, or the fvar default itself if there are no named stops.
	static func defaultValue(for axis: VariableFontAxis) -> Double {
		if let elidable = axis.stops.first(where: { $0.isElidable }) {
			return elidable.value
		}
		if let closest = axis.stops.min(by: { abs($0.value - axis.defaultValue) < abs($1.value - axis.defaultValue) }) {
			return closest.value
		}
		return axis.defaultValue
	}
}

/// A drag-based slider that snaps to an axis's STAT stops, moving freely
/// only while Shift is held.
private struct ContinuousAxisSlider: View {
	let axis: VariableFontAxis
	@Binding var value: Double

	var body: some View {
		GeometryReader { geometry in
			let width = geometry.size.width
			ZStack(alignment: .leading) {
				Capsule()
					.fill(Color.secondary.opacity(0.25))
					.frame(height: 4)
				ForEach(axis.stops) { stop in
					Circle()
						.fill(Color.secondary.opacity(0.6))
						.frame(width: 4, height: 4)
						.offset(x: xPosition(for: stop.value, width: width) - 2)
				}
				Circle()
					.fill(Color.accentColor)
					.frame(width: 14, height: 14)
					.offset(x: xPosition(for: value, width: width) - 7)
					.gesture(
						DragGesture(minimumDistance: 0)
							.onChanged { drag in
								let fraction = min(max(drag.location.x / width, 0), 1)
								let raw = axis.minValue + Double(fraction) * (axis.maxValue - axis.minValue)
								if NSEvent.modifierFlags.contains(.shift) {
									value = raw
								} else {
									value = nearestStop(to: raw)
								}
							}
					)
			}
		}
		.frame(height: 16)
	}

	private func xPosition(for axisValue: Double, width: CGFloat) -> CGFloat {
		guard axis.maxValue > axis.minValue else {
			return 0
		}
		let fraction = (axisValue - axis.minValue) / (axis.maxValue - axis.minValue)
		return CGFloat(min(max(fraction, 0), 1)) * width
	}

	private func nearestStop(to raw: Double) -> Double {
		guard !axis.stops.isEmpty else {
			return raw
		}
		return axis.stops.min(by: { abs($0.value - raw) < abs($1.value - raw) })?.value ?? raw
	}
}
