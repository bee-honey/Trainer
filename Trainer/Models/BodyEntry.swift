import Foundation
import SwiftData

/// A manual body check-in. Stored in kg / cm; shown in the user's unit.
@Model
final class BodyEntry {
    var date: Date
    var weightKg: Double?
    var waistCm: Double?
    var chestCm: Double?
    var armsCm: Double?
    var hipsCm: Double?
    var thighsCm: Double?

    init(date: Date) {
        self.date = date
    }
}

enum BodyMeasurement: String, CaseIterable, Identifiable {
    case waist = "Waist", chest = "Chest", arms = "Arms", hips = "Hips", thighs = "Thighs"

    var id: String { rawValue }

    var keyPath: ReferenceWritableKeyPath<BodyEntry, Double?> {
        switch self {
        case .waist: \.waistCm
        case .chest: \.chestCm
        case .arms: \.armsCm
        case .hips: \.hipsCm
        case .thighs: \.thighsCm
        }
    }
}

/// "lb" → pounds + inches, "kg" → kilograms + centimetres.
enum Units {
    static func weight(_ kg: Double, _ unit: String) -> Double { unit == "lb" ? kg * 2.20462 : kg }
    static func kg(from value: Double, _ unit: String) -> Double { unit == "lb" ? value / 2.20462 : value }
    static func length(_ cm: Double, _ unit: String) -> Double { unit == "lb" ? cm / 2.54 : cm }
    static func cm(from value: Double, _ unit: String) -> Double { unit == "lb" ? value * 2.54 : value }
    static func lengthUnit(_ unit: String) -> String { unit == "lb" ? "in" : "cm" }
}
