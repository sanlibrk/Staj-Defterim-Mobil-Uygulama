import Foundation

/// Writes the stored entries and directory of an OPC package using the classic ZIP format.
struct DOCXArchive {
    let file: FileHandle
    private var offset: UInt64 = 0
    private var directory = Data()
    private var entryCount: UInt16 = 0

    private let utf8Flag: UInt16 = 0x0800
    private let zipVersion: UInt16 = 20
    private let dosEpochDate: UInt16 = 0x0021

    init(file: FileHandle) {
        self.file = file
    }

    mutating func add(_ path: String, text: String) throws {
        try add(path, data: Data(text.utf8))
    }

    mutating func add(_ path: String, data: Data) throws {
        let name = Data(path.utf8)
        // The maximum field values are reserved as ZIP64 markers.
        guard entryCount < UInt16.max - 1,
              let nameLength = UInt16(exactly: name.count),
              data.count < UInt32.max,
              offset + UInt64(30 + name.count) + UInt64(data.count) < UInt32.max else {
            throw DOCXExportError.archiveTooLarge
        }
        let size = UInt32(data.count)
        let checksum = Self.checksum(data)

        var header = Data()
        header.append32(0x04034B50)
        appendEntryInfo(to: &header, checksum: checksum, size: size, nameLength: nameLength)
        header.append16(0) // Extra field length
        header.append(name)
        try file.write(contentsOf: header)
        try file.write(contentsOf: data)

        var centralEntry = Data()
        centralEntry.append32(0x02014B50)
        centralEntry.append16(zipVersion) // Version made by, with the DOS host code
        appendEntryInfo(to: &centralEntry, checksum: checksum, size: size, nameLength: nameLength)
        centralEntry.append16(0) // Extra field length
        centralEntry.append16(0) // File comment length
        centralEntry.append16(0) // Starting disk number
        centralEntry.append16(0) // Internal file attributes
        centralEntry.append32(0) // External file attributes
        centralEntry.append32(UInt32(offset))
        centralEntry.append(name)
        directory.append(centralEntry)

        offset += UInt64(header.count) + UInt64(data.count)
        entryCount += 1
    }

    func finish() throws {
        guard offset + UInt64(directory.count) + 22 < UInt32.max else {
            throw DOCXExportError.archiveTooLarge
        }

        var end = Data()
        end.append32(0x06054B50)
        end.append16(0) // Current disk number
        end.append16(0) // Central directory disk number
        end.append16(entryCount)
        end.append16(entryCount)
        end.append32(UInt32(directory.count))
        end.append32(UInt32(offset))
        end.append16(0) // Archive comment length
        try file.write(contentsOf: directory)
        try file.write(contentsOf: end)
    }

    private func appendEntryInfo(to data: inout Data, checksum: UInt32, size: UInt32, nameLength: UInt16) {
        data.append16(zipVersion)
        data.append16(utf8Flag)
        data.append16(0) // Store the already-compressed JPEGs as-is.
        data.append16(0) // Modification time at midnight
        data.append16(dosEpochDate)
        data.append32(checksum)
        data.append32(size) // Compressed byte count
        data.append32(size) // Uncompressed byte count
        data.append16(nameLength)
    }

    private static let crcTable: [UInt32] = (0...255).map { byte in
        var crc = UInt32(byte)
        for _ in 0..<8 {
            let polynomial: UInt32 = crc & 1 == 0 ? 0 : 0xEDB88320
            crc = (crc >> 1) ^ polynomial
        }
        return crc
    }

    private static func checksum(_ data: Data) -> UInt32 {
        let table = crcTable
        var crc = UInt32.max
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            for byte in bytes {
                let index = Int((crc ^ UInt32(byte)) & 0xFF)
                crc = (crc >> 8) ^ table[index]
            }
        }
        return crc ^ UInt32.max
    }
}

private extension Data {
    mutating func append16(_ number: UInt16) {
        var bytes = number.littleEndian
        Swift.withUnsafeBytes(of: &bytes) { append(contentsOf: $0) }
    }

    mutating func append32(_ number: UInt32) {
        var bytes = number.littleEndian
        Swift.withUnsafeBytes(of: &bytes) { append(contentsOf: $0) }
    }
}
