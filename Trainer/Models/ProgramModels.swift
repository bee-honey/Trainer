import Foundation
import SwiftData
import UIKit

// The user's program, stored with SwiftData and synced through iCloud (CloudKit).
// CloudKit rules: every attribute has a default, every relationship is optional,
// no unique constraints, and ordering is an explicit `order` field.
// `key` identifies a record across devices; `updatedAt` decides which copy wins
// when the same record is created on two devices (see ProgramSeeder.dedupe).

/// A library exercise: name, photos, tags, tip, and the sets it starts with
/// when added to a workout.
@Model
final class Exercise {
    var key: String = UUID().uuidString
    var name: String = ""
    var muscle: String = ""
    var equipment: String = ""
    var tagsText: String = ""          // comma-separated custom tags
    var tip: String = ""
    var bundledImage: String?          // default photo shipped in the app
    var defaultRest: Int = 60
    var defaultSetsData: Data?
    var isCustom: Bool = true
    var updatedAt: Date = Date.distantPast

    @Relationship(deleteRule: .cascade, inverse: \ExercisePhoto.exercise)
    var photos: [ExercisePhoto]? = []
    @Relationship(deleteRule: .nullify, inverse: \WorkoutItem.exercise)
    var items: [WorkoutItem]? = []

    init(key: String = UUID().uuidString, name: String = "") {
        self.key = key
        self.name = name
    }

    var tags: [String] {
        get { tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        set { tagsText = newValue.joined(separator: ",") }
    }

    var defaultSets: [ProgramSet] {
        get { defaultSetsData.flatMap { try? JSONDecoder().decode([ProgramSet].self, from: $0) } ?? [] }
        set { defaultSetsData = try? JSONEncoder().encode(newValue) }
    }

    var sortedPhotos: [ExercisePhoto] { (photos ?? []).sorted { $0.order < $1.order } }

    var photoRefs: [PhotoRef] {
        (bundledImage.map { [.bundled($0)] } ?? []) + sortedPhotos.map { .stored($0.persistentModelID) }
    }

    /// Workouts that use this exercise, by title.
    var workoutTitles: [String] {
        Array(Set((items ?? []).compactMap { $0.workout?.title })).sorted()
    }

    /// First photo, small, for list rows.
    var thumbnail: UIImage? {
        let source: UIImage? = if let name = bundledImage {
            Bundle.main.path(forResource: name, ofType: "jpg").flatMap(UIImage.init(contentsOfFile:))
        } else {
            sortedPhotos.first?.data.flatMap(UIImage.init(data:))
        }
        guard let source else { return nil }
        let width: CGFloat = 160
        return source.preparingThumbnail(of: CGSize(width: width, height: width * source.size.height / max(source.size.width, 1)))
    }
}

@Model
final class ExercisePhoto {
    @Attribute(.externalStorage) var data: Data?
    var order: Int = 0
    var exercise: Exercise?

    init(data: Data, order: Int) {
        self.data = data
        self.order = order
    }
}

/// One of the program's workouts (e.g. "Shoulder (Push Emphasis) & Triceps") and
/// the program days it's scheduled on (e.g. 1, 8, 15, 22, 29).
@Model
final class Workout {
    var key: String = UUID().uuidString
    var title: String = ""
    var dayNumbersText: String = ""
    var order: Int = 0
    var updatedAt: Date = Date.distantPast

    @Relationship(deleteRule: .cascade, inverse: \WorkoutItem.workout)
    var items: [WorkoutItem]? = []

    init(key: String, title: String, dayNumbers: [Int], order: Int) {
        self.key = key
        self.title = title
        self.order = order
        self.dayNumbers = dayNumbers
    }

    var dayNumbers: [Int] {
        get { dayNumbersText.split(separator: ",").compactMap { Int($0) } }
        set { dayNumbersText = newValue.map(String.init).joined(separator: ",") }
    }

    var sortedItems: [WorkoutItem] { (items ?? []).sorted { $0.order < $1.order } }
}

/// An exercise placed in a workout, with this workout's own sets.
@Model
final class WorkoutItem {
    var key: String = UUID().uuidString
    var order: Int = 0
    var setsData: Data?
    var workout: Workout?
    var exercise: Exercise?

    init(key: String = UUID().uuidString, order: Int, sets: [ProgramSet]) {
        self.key = key
        self.order = order
        self.sets = sets
    }

    var sets: [ProgramSet] {
        get { setsData.flatMap { try? JSONDecoder().decode([ProgramSet].self, from: $0) } ?? [] }
        set { setsData = try? JSONEncoder().encode(newValue) }
    }
}

extension ProgramExercise {
    init?(item: WorkoutItem) {
        guard let e = item.exercise else { return nil }
        self.init(key: item.key, exerciseKey: e.key, name: e.name, muscle: e.muscle, equipment: e.equipment,
                  tags: e.tags, tip: e.tip.isEmpty ? nil : e.tip, sets: item.sets, photos: e.photoRefs)
    }
}

enum PhotoLoader {
    static func image(_ ref: PhotoRef, in context: ModelContext) -> UIImage? {
        switch ref {
        case .bundled(let name):
            return Bundle.main.path(forResource: name, ofType: "jpg").flatMap(UIImage.init(contentsOfFile:))
        case .stored(let id):
            return (context.model(for: id) as? ExercisePhoto)?.data.flatMap(UIImage.init(data:))
        }
    }

    /// Picked photos are resized to 1600px JPEG so iCloud sync stays light.
    static func prepared(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(1, 1600 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format)
            .image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            .jpegData(compressionQuality: 0.8)
    }
}
