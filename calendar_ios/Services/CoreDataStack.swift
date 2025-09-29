import Foundation
import CoreData

final class CoreDataStack {
    static let shared = CoreDataStack()

    let container: NSPersistentContainer

    private init() {
        let model = CoreDataStack.makeModel()
        container = NSPersistentContainer(name: "calendar_ios", managedObjectModel: model)
        container.loadPersistentStores { _, error in
            if let error {
                assertionFailure("Failed to load Core Data store: \(error)")
            }
        }
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.undoManager = nil
        return context
    }

    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        let entity = NSEntityDescription()
        entity.name = "EventEntity"
        entity.managedObjectClassName = NSStringFromClass(EventEntity.self)

        func attribute(_ name: String, type: NSAttributeType, optional: Bool = true, defaultValue: Any? = nil) -> NSAttributeDescription {
            let description = NSAttributeDescription()
            description.name = name
            description.attributeType = type
            description.isOptional = optional
            description.defaultValue = defaultValue
            return description
        }

        let id = attribute("id", type: .stringAttributeType, optional: false)
        let title = attribute("title", type: .stringAttributeType, optional: false)
        let startDate = attribute("startDate", type: .dateAttributeType, optional: false)
        let endDate = attribute("endDate", type: .dateAttributeType, optional: false)
        let isAllDay = attribute("isAllDay", type: .booleanAttributeType, optional: false, defaultValue: false)
        let location = attribute("location", type: .stringAttributeType)
        let calendarId = attribute("calendarId", type: .stringAttributeType, optional: false)
        let eventDescription = attribute("eventDescription", type: .stringAttributeType)
        let customColorHex = attribute("customColorHex", type: .stringAttributeType)
        let recurrenceRule = attribute("recurrenceRule", type: .stringAttributeType)
        let remindersData = attribute("remindersData", type: .binaryDataAttributeType)
        let url = attribute("url", type: .stringAttributeType)
        let calendarName = attribute("calendarName", type: .stringAttributeType)
        let isFromDeviceCalendar = attribute("isFromDeviceCalendar", type: .booleanAttributeType, optional: false, defaultValue: false)
        let deviceEventId = attribute("deviceEventId", type: .stringAttributeType)
        let createdAt = attribute("createdAt", type: .dateAttributeType)
        let updatedAt = attribute("updatedAt", type: .dateAttributeType)

        entity.properties = [
            id,
            title,
            startDate,
            endDate,
            isAllDay,
            location,
            calendarId,
            eventDescription,
            customColorHex,
            recurrenceRule,
            remindersData,
            url,
            calendarName,
            isFromDeviceCalendar,
            deviceEventId,
            createdAt,
            updatedAt
        ]

        model.entities = [entity]
        return model
    }
}
