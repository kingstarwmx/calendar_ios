import Foundation
import CoreData

actor DatabaseHelper {
    static let shared = DatabaseHelper()

    private let stack: CoreDataStack

    init(stack: CoreDataStack = .shared) {
        self.stack = stack
    }

    // MARK: - CRUD

    func saveEvent(_ event: Event) async throws {
        try await perform(save: true) { context in
            let entity = try self.fetchEntity(with: event.id, in: context) ?? EventEntity(context: context)
            event.apply(to: entity)
        }
    }

    func updateEvent(_ event: Event) async throws {
        try await saveEvent(event)
    }

    func deleteEvent(id: String) async throws {
        try await perform(save: true) { context in
            guard let entity = try self.fetchEntity(with: id, in: context) else { return }
            context.delete(entity)
        }
    }

    func fetchEvent(id: String) async -> Event? {
        await performResult(fallback: nil) { context in
            let entity = try self.fetchEntity(with: id, in: context)
            return entity.flatMap(Event.init(entity:))
        }
    }

    func fetchEvents(for date: Date) async -> [Event] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? date
        return await fetchEventsInRange(start: dayStart, end: dayEnd)
    }

    func fetchEventsInRange(start: Date, end: Date) async -> [Event] {
        await performResult(fallback: []) { context in
            let request = EventEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "(startDate <= %@ AND endDate >= %@)", end as NSDate, start as NSDate
            )
            request.sortDescriptors = [
                NSSortDescriptor(key: #keyPath(EventEntity.startDate), ascending: true),
                NSSortDescriptor(key: #keyPath(EventEntity.endDate), ascending: true)
            ]
            return try context.fetch(request).compactMap(Event.init(entity:))
        }
    }

    func fetchAllEvents() async -> [Event] {
        await performResult(fallback: []) { context in
            let request = EventEntity.fetchRequest()
            request.sortDescriptors = [
                NSSortDescriptor(key: #keyPath(EventEntity.startDate), ascending: true)
            ]
            return try context.fetch(request).compactMap(Event.init(entity:))
        }
    }

    // MARK: - Helpers

    private func fetchEntity(with id: String, in context: NSManagedObjectContext) throws -> EventEntity? {
        let request = EventEntity.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id)
        return try context.fetch(request).first
    }

    private func perform<T>(save: Bool = false, _ block: @escaping (NSManagedObjectContext) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let context = stack.newBackgroundContext()
            context.perform {
                do {
                    let value = try block(context)
                    if save, context.hasChanges {
                        try context.save()
                    }
                    continuation.resume(returning: value)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func performResult<T>(fallback: T, _ block: @escaping (NSManagedObjectContext) throws -> T) async -> T {
        await withCheckedContinuation { continuation in
            let context = stack.newBackgroundContext()
            context.perform {
                do {
                    let value = try block(context)
                    continuation.resume(returning: value)
                } catch {
                    assertionFailure("Database fetch failed: \(error)")
                    continuation.resume(returning: fallback)
                }
            }
        }
    }
}
