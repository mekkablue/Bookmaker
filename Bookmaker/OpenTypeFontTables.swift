import CoreText
import Foundation

/// One named stop along a variable font axis, from the OpenType `STAT`
/// table's AxisValue records.
struct VariableFontStop: Identifiable, Equatable {
	var name: String
	var value: Double
	/// STAT's ElidableAxisValueName flag: this stop represents "no
	/// adjustment" and is the natural default position for a slider.
	var isElidable: Bool

	var id: String { "\(name)-\(value)" }
}

/// One axis of a variable font, combining `fvar` (the continuous range this
/// specific font file can interpolate) with `STAT` (named stops along the
/// axis, which may span sibling files, e.g. a separate italic).
struct VariableFontAxis: Identifiable, Equatable {
	var tag: String
	var name: String
	var minValue: Double
	var maxValue: Double
	var defaultValue: Double
	/// True when this font file can continuously interpolate this axis
	/// (the axis is present in the file's own `fvar` table). False means
	/// the axis is known only from `STAT` as discrete stops that live in
	/// sibling files — typically an "ital" axis split into separate files.
	var isContinuousInThisFile: Bool
	var stops: [VariableFontStop]

	var id: String { tag }
}

/// Low-level, spec-accurate parsers for the OpenType `STAT` and `name`
/// tables. CoreText exposes `fvar` axes via `CTFontCopyVariationAxes`, but
/// has no public API for STAT's per-axis named stops or their "elidable"
/// flag, so those are read directly from the raw table bytes here.
enum OpenTypeTables {
	struct RawAxisValue {
		var format: Int
		var axisIndex: Int
		var value: Double
		var flags: Int
		var valueNameID: Int
		/// Format 4 only: this stop is only meaningful as the combination
		/// of values across all of these axes (e.g. Bold + Italic together).
		var multiAxis: [(axisIndex: Int, value: Double)] = []
	}

	struct STATResult {
		var axisTags: [String]
		var axisNameIDs: [Int]
		var values: [RawAxisValue]
	}

	static func parseSTAT(_ data: Data) -> STATResult? {
		guard data.count >= 16, data.uint16(at: 0) == 1 else {
			return nil
		}
		let designAxisSize = Int(data.uint16(at: 4))
		let designAxisCount = Int(data.uint16(at: 6))
		let designAxesOffset = Int(data.uint32(at: 8))
		let axisValueCount = Int(data.uint16(at: 12))
		let offsetToAxisValueOffsets = Int(data.uint32(at: 14))

		guard designAxisSize >= 8 else {
			return nil
		}

		var tags: [String] = []
		var nameIDs: [Int] = []
		for i in 0..<designAxisCount {
			let recordOffset = designAxesOffset + i * designAxisSize
			guard recordOffset + 8 <= data.count else {
				break
			}
			tags.append(data.tag4(at: recordOffset))
			nameIDs.append(Int(data.uint16(at: recordOffset + 4)))
		}

		var values: [RawAxisValue] = []
		if axisValueCount > 0, offsetToAxisValueOffsets > 0 {
			for i in 0..<axisValueCount {
				let offsetFieldPos = offsetToAxisValueOffsets + i * 2
				guard offsetFieldPos + 2 <= data.count else {
					break
				}
				let relOffset = Int(data.uint16(at: offsetFieldPos))
				let recordOffset = offsetToAxisValueOffsets + relOffset
				guard recordOffset + 2 <= data.count else {
					continue
				}
				let format = Int(data.uint16(at: recordOffset))
				switch format {
				case 1:
					guard recordOffset + 12 <= data.count else { continue }
					values.append(RawAxisValue(
						format: 1,
						axisIndex: Int(data.uint16(at: recordOffset + 2)),
						value: data.fixed(at: recordOffset + 8),
						flags: Int(data.uint16(at: recordOffset + 4)),
						valueNameID: Int(data.uint16(at: recordOffset + 6))
					))
				case 2:
					guard recordOffset + 20 <= data.count else { continue }
					// nominal value is used as the stop's position on the axis
					values.append(RawAxisValue(
						format: 2,
						axisIndex: Int(data.uint16(at: recordOffset + 2)),
						value: data.fixed(at: recordOffset + 8),
						flags: Int(data.uint16(at: recordOffset + 4)),
						valueNameID: Int(data.uint16(at: recordOffset + 6))
					))
				case 3:
					guard recordOffset + 16 <= data.count else { continue }
					values.append(RawAxisValue(
						format: 3,
						axisIndex: Int(data.uint16(at: recordOffset + 2)),
						value: data.fixed(at: recordOffset + 8),
						flags: Int(data.uint16(at: recordOffset + 4)),
						valueNameID: Int(data.uint16(at: recordOffset + 6))
					))
				case 4:
					guard recordOffset + 8 <= data.count else { continue }
					let axisCount = Int(data.uint16(at: recordOffset + 2))
					var multi: [(axisIndex: Int, value: Double)] = []
					for j in 0..<axisCount {
						let entryOffset = recordOffset + 8 + j * 6
						guard entryOffset + 6 <= data.count else { break }
						multi.append((Int(data.uint16(at: entryOffset)), data.fixed(at: entryOffset + 2)))
					}
					values.append(RawAxisValue(
						format: 4,
						axisIndex: multi.first?.axisIndex ?? -1,
						value: multi.first?.value ?? 0,
						flags: Int(data.uint16(at: recordOffset + 4)),
						valueNameID: Int(data.uint16(at: recordOffset + 6)),
						multiAxis: multi
					))
				default:
					continue
				}
			}
		}
		return STATResult(axisTags: tags, axisNameIDs: nameIDs, values: values)
	}

	/// Resolves `name` table nameIDs to strings, preferring Windows Unicode
	/// BMP (platform 3, encoding 1, US English) and falling back to
	/// Macintosh Roman or any other localized record found.
	static func parseName(_ data: Data) -> [Int: String] {
		guard data.count >= 6 else {
			return [:]
		}
		let count = Int(data.uint16(at: 2))
		let stringOffset = Int(data.uint16(at: 4))
		var best: [Int: (score: Int, string: String)] = [:]

		for i in 0..<count {
			let recordOffset = 6 + i * 12
			guard recordOffset + 12 <= data.count else {
				break
			}
			let platformID = Int(data.uint16(at: recordOffset))
			let encodingID = Int(data.uint16(at: recordOffset + 2))
			let languageID = Int(data.uint16(at: recordOffset + 4))
			let nameID = Int(data.uint16(at: recordOffset + 6))
			let length = Int(data.uint16(at: recordOffset + 8))
			let relativeStringOffset = Int(data.uint16(at: recordOffset + 10))
			let absoluteOffset = stringOffset + relativeStringOffset
			guard absoluteOffset >= 0, absoluteOffset + length <= data.count else {
				continue
			}
			let bytes = data.subdata(in: (data.startIndex + absoluteOffset)..<(data.startIndex + absoluteOffset + length))

			let string: String?
			let score: Int
			if platformID == 3, encodingID == 1 {
				string = String(bytes: bytes, encoding: .utf16BigEndian)
				score = languageID == 0x409 ? 3 : 2
			} else if platformID == 0 {
				string = String(bytes: bytes, encoding: .utf16BigEndian)
				score = 2
			} else if platformID == 1, encodingID == 0 {
				string = String(bytes: bytes, encoding: .macOSRoman)
				score = languageID == 0 ? 2 : 1
			} else {
				string = String(bytes: bytes, encoding: .utf16BigEndian) ?? String(bytes: bytes, encoding: .isoLatin1)
				score = 0
			}
			guard let resolved = string, !resolved.isEmpty else {
				continue
			}
			if let existing = best[nameID], existing.score >= score {
				continue
			}
			best[nameID] = (score, resolved)
		}
		return best.mapValues { $0.string }
	}
}

private extension Data {
	func uint16(at offset: Int) -> UInt16 {
		guard offset >= 0, offset + 2 <= count else {
			return 0
		}
		return withUnsafeBytes { raw -> UInt16 in
			let base = raw.baseAddress!.advanced(by: offset)
			let b0 = base.load(fromByteOffset: 0, as: UInt8.self)
			let b1 = base.load(fromByteOffset: 1, as: UInt8.self)
			return (UInt16(b0) << 8) | UInt16(b1)
		}
	}

	func uint32(at offset: Int) -> UInt32 {
		guard offset >= 0, offset + 4 <= count else {
			return 0
		}
		return withUnsafeBytes { raw -> UInt32 in
			let base = raw.baseAddress!.advanced(by: offset)
			let b0 = base.load(fromByteOffset: 0, as: UInt8.self)
			let b1 = base.load(fromByteOffset: 1, as: UInt8.self)
			let b2 = base.load(fromByteOffset: 2, as: UInt8.self)
			let b3 = base.load(fromByteOffset: 3, as: UInt8.self)
			return (UInt32(b0) << 24) | (UInt32(b1) << 16) | (UInt32(b2) << 8) | UInt32(b3)
		}
	}

	/// OpenType `Fixed`: signed 16.16 fixed-point.
	func fixed(at offset: Int) -> Double {
		Double(Int32(bitPattern: uint32(at: offset))) / 65536.0
	}

	func tag4(at offset: Int) -> String {
		guard offset >= 0, offset + 4 <= count else {
			return ""
		}
		let bytes = withUnsafeBytes { raw -> [UInt8] in
			let base = raw.baseAddress!.advanced(by: offset)
			return (0..<4).map { base.load(fromByteOffset: $0, as: UInt8.self) }
		}
		return String(bytes: bytes, encoding: .ascii) ?? ""
	}
}

/// Reads `fvar` (via CoreText) and `STAT` (via raw table parsing) for a
/// specific font resource, producing the axis list a variable-font picker
/// needs.
enum VariableFontIntrospector {
	struct FaceInfo: Identifiable, Equatable {
		var postscriptName: String
		var displayName: String
		var isVariable: Bool
		var axes: [VariableFontAxis]
		var id: String { postscriptName }
	}

	static func introspect(descriptor: CTFontDescriptor) -> FaceInfo {
		let font = CTFontCreateWithFontDescriptor(descriptor, 0, nil)
		let postscriptName = (CTFontCopyPostScriptName(font) as String)
		let displayName = (CTFontCopyName(font, kCTFontSubFamilyNameKey) as String?) ?? (CTFontCopyDisplayName(font) as String)

		var fvarAxes: [String: (min: Double, max: Double, def: Double, name: String)] = [:]
		if let axesArray = CTFontCopyVariationAxes(font) as? [[String: Any]] {
			for axisDict in axesArray {
				guard let identifier = axisDict[kCTFontVariationAxisIdentifierKey as String] as? NSNumber,
					  let minValue = axisDict[kCTFontVariationAxisMinimumValueKey as String] as? NSNumber,
					  let maxValue = axisDict[kCTFontVariationAxisMaximumValueKey as String] as? NSNumber,
					  let defaultValue = axisDict[kCTFontVariationAxisDefaultValueKey as String] as? NSNumber else {
					continue
				}
				let tag = fourCharCode(from: identifier.uint32Value)
				let name = (axisDict[kCTFontVariationAxisNameKey as String] as? String) ?? tag
				fvarAxes[tag] = (minValue.doubleValue, maxValue.doubleValue, defaultValue.doubleValue, name)
			}
		}

		var axes: [VariableFontAxis] = []
		if let statData = CTFontCopyTable(font, fourCharTag("STAT"), CTFontTableOptions(rawValue: 0)) as Data?,
		   let stat = OpenTypeTables.parseSTAT(statData) {
			var nameTable: [Int: String] = [:]
			if let nameData = CTFontCopyTable(font, fourCharTag("name"), CTFontTableOptions(rawValue: 0)) as Data? {
				nameTable = OpenTypeTables.parseName(nameData)
			}
			for (axisIndex, tag) in stat.axisTags.enumerated() {
				let axisName = nameTable[stat.axisNameIDs[axisIndex]] ?? tag
				let fvar = fvarAxes[tag]
				var stops: [VariableFontStop] = []
				for raw in stat.values {
					if raw.format == 4 {
						for entry in raw.multiAxis where entry.axisIndex == axisIndex {
							let name = nameTable[raw.valueNameID] ?? axisName
							stops.append(VariableFontStop(name: name, value: entry.value, isElidable: raw.flags & 0x2 != 0))
						}
					} else if raw.axisIndex == axisIndex {
						let name = nameTable[raw.valueNameID] ?? axisName
						stops.append(VariableFontStop(name: name, value: raw.value, isElidable: raw.flags & 0x2 != 0))
					}
				}
				stops.sort { $0.value < $1.value }
				let isContinuous = fvar != nil
				let minValue = fvar?.min ?? (stops.map(\.value).min() ?? 0)
				let maxValue = fvar?.max ?? (stops.map(\.value).max() ?? 0)
				let defaultValue = fvar?.def ?? (stops.first?.value ?? 0)
				axes.append(VariableFontAxis(
					tag: tag,
					name: axisName,
					minValue: minValue,
					maxValue: maxValue,
					defaultValue: defaultValue,
					isContinuousInThisFile: isContinuous,
					stops: stops
				))
			}
		} else if !fvarAxes.isEmpty {
			// no STAT table: fall back to plain fvar axes with no named stops
			for (tag, fvar) in fvarAxes.sorted(by: { $0.key < $1.key }) {
				axes.append(VariableFontAxis(
					tag: tag,
					name: fvar.name,
					minValue: fvar.min,
					maxValue: fvar.max,
					defaultValue: fvar.def,
					isContinuousInThisFile: true,
					stops: []
				))
			}
		}

		return FaceInfo(postscriptName: postscriptName, displayName: displayName, isVariable: !fvarAxes.isEmpty, axes: axes)
	}

	private static func fourCharCode(from value: UInt32) -> String {
		let bytes: [UInt8] = [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
		return String(bytes: bytes, encoding: .ascii) ?? ""
	}

	private static func fourCharTag(_ tag: String) -> CTFontTableTag {
		var result: UInt32 = 0
		for scalar in tag.unicodeScalars.prefix(4) {
			result = (result << 8) | (scalar.value & 0xFF)
		}
		return CTFontTableTag(result)
	}
}

/// Enumerates the fonts installed on this machine, for the system font picker.
enum SystemFontCatalog {
	static func familyNames() -> [String] {
		(CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? []).sorted()
	}

	static func faces(inFamily family: String) -> [CTFontDescriptor] {
		let attributes: [CFString: Any] = [kCTFontFamilyNameAttribute: family]
		let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
		return CTFontDescriptorCreateMatchingFontDescriptors(descriptor, nil) as? [CTFontDescriptor] ?? []
	}
}
