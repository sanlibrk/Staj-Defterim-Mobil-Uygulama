import Foundation

/// A Gregorian calendar day that retains its date when the device changes time zones.
public struct LocalDate: Codable, Hashable, Comparable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(_ date: Date, timeZone: TimeZone = .current) {
        let components = Self.calendar(in: timeZone).dateComponents([.year, .month, .day], from: date)
        year = components.year!
        month = components.month!
        day = components.day!
    }

    public init?(year: Int, month: Int, day: Int) {
        guard (1...9999).contains(year), (1...12).contains(month) else { return nil }
        let isLeapYear = year.isMultiple(of: 4) && (!year.isMultiple(of: 100) || year.isMultiple(of: 400))
        let daysInMonth = [31, isLeapYear ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard (1...daysInMonth[month - 1]).contains(day) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Noon in the current time zone is suitable for bridging to a date-only picker.
    public var date: Date {
        Self.calendar(in: .current).date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    public var iso8601: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        let components = value.split(separator: "-")
        guard components.count == 3,
              let year = Int(components[0]), let month = Int(components[1]), let day = Int(components[2]),
              let date = Self(year: year, month: month, day: day), date.iso8601 == value else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid Gregorian calendar date")
        }
        self = date
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(iso8601)
    }

    private static func calendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

public struct Internship: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var studentName: String
    public var school: String
    public var department: String
    public var studentNumber: String
    public var workplace: String
    public var startDate: LocalDate
    public var endDate: LocalDate
    public var entries: [JournalEntry]

    public init(
        id: UUID = UUID(),
        studentName: String = "",
        school: String = "",
        department: String = "",
        studentNumber: String = "",
        workplace: String = "",
        startDate: LocalDate = LocalDate(Date()),
        endDate: LocalDate = LocalDate(Date()),
        entries: [JournalEntry] = []
    ) {
        self.id = id
        self.studentName = studentName
        self.school = school
        self.department = department
        self.studentNumber = studentNumber
        self.workplace = workplace
        self.startDate = startDate
        self.endDate = endDate
        self.entries = entries
    }
}

public struct JournalEntry: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var date: LocalDate
    public var work: String
    public var method: String
    public var result: String
    public var learning: String
    public var photos: [JournalPhoto]

    public init(
        id: UUID = UUID(),
        date: LocalDate = LocalDate(Date()),
        work: String = "",
        method: String = "",
        result: String = "",
        learning: String = "",
        photos: [JournalPhoto] = []
    ) {
        self.id = id
        self.date = date
        self.work = work
        self.method = method
        self.result = result
        self.learning = learning
        self.photos = photos
    }
}

public struct JournalPhoto: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var caption: String

    public init(id: UUID = UUID(), caption: String = "") {
        self.id = id
        self.caption = caption
    }
}
