import Foundation
import CoreData

@objc(EventEntity)
final class EventEntity: NSManagedObject {
    @NSManaged var id: String?
    @NSManaged var title: String?
    @NSManaged var startDate: Date?
    @NSManaged var endDate: Date?
    @NSManaged var isAllDay: Bool
    @NSManaged var location: String?
    @NSManaged var calendarId: String?
    @NSManaged var eventDescription: String?
    @NSManaged var customColorHex: String?
    @NSManaged var recurrenceRule: String?
    @NSManaged var remindersData: Data?
    @NSManaged var url: String?
    @NSManaged var calendarName: String?
    @NSManaged var isFromDeviceCalendar: Bool
    @NSManaged var deviceEventId: String?
    @NSManaged var createdAt: Date?
    @NSManaged var updatedAt: Date?
}

extension EventEntity {
    @nonobjc class func fetchRequest() -> NSFetchRequest<EventEntity> {
        NSFetchRequest<EventEntity>(entityName: "EventEntity")
    }
}
