import Foundation

public enum DOCXExportError: LocalizedError, Equatable {
    case missingPhoto
    case invalidPhoto
    case archiveTooLarge
    case cannotCreateArchive

    public var errorDescription: String? {
        switch self {
        case .missingPhoto:
            "Kayıtlardaki bir fotoğraf bulunamadı."
        case .invalidPhoto:
            "Kayıtlardaki bir fotoğraf okunamadı."
        case .archiveTooLarge:
            "Belge DOCX dosyası için çok büyük."
        case .cannotCreateArchive:
            "DOCX dosyası oluşturulamadı."
        }
    }
}

public enum DOCXExporter {
    /// Writes a new document to an unused URL in an existing directory.
    public static func export(
        internship: Internship,
        photoData: [UUID: Data],
        to destination: URL
    ) throws {
        let fileManager = FileManager.default
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).docx.tmp")
        guard fileManager.createFile(atPath: staging.path, contents: nil) else {
            throw DOCXExportError.cannotCreateArchive
        }
        defer { try? fileManager.removeItem(at: staging) }

        let file = try FileHandle(forWritingTo: staging)
        do {
            var archive = DOCXArchive(file: file)
            try writeParts(internship: internship, photoData: photoData, archive: &archive)
            try archive.finish()
        } catch {
            try? file.close()
            throw error
        }
        try file.close()
        try fileManager.moveItem(at: staging, to: destination)
    }

    private static func writeParts(
        internship: Internship,
        photoData: [UUID: Data],
        archive: inout DOCXArchive
    ) throws {
        try archive.add("[Content_Types].xml", text: contentTypes)
        try archive.add("_rels/.rels", text: packageRelationships)
        try archive.add("word/styles.xml", text: styles)

        var body = paragraph("Staj Defteri", style: "Title")
        let details = [
            ("Öğrenci", internship.studentName),
            ("Öğrenci numarası", internship.studentNumber),
            ("Okul", internship.school),
            ("Bölüm", internship.department),
            ("Staj yeri", internship.workplace),
            ("Başlangıç tarihi", dateLabel(internship.startDate)),
            ("Bitiş tarihi", dateLabel(internship.endDate)),
        ]
        for (label, value) in details {
            body += paragraph(label, style: "Label")
            body += paragraph(value)
        }

        var relationships = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        """
        var imageNumber = 0

        for entry in internship.entries.sorted(by: { $0.date < $1.date }) {
            body += paragraph(dateLabel(entry.date), style: "Heading1", startPage: true)
            let sections = [
                ("Ne yaptım", entry.work),
                ("Nasıl yaptım", entry.method),
                ("Sonuç", entry.result),
                ("Öğrendiklerim", entry.learning),
            ]
            for (label, value) in sections {
                body += paragraph(label, style: "Heading2")
                body += paragraph(value)
            }

            if !entry.photos.isEmpty {
                body += paragraph("Fotoğraflar", style: "Heading2")
            }
            for photo in entry.photos {
                guard let data = photoData[photo.id] else { throw DOCXExportError.missingPhoto }
                guard let size = jpegSize(data) else { throw DOCXExportError.invalidPhoto }

                imageNumber += 1
                let part = "media/foto-\(imageNumber).jpg"
                let relationshipID = "rId\(imageNumber + 1)"
                try archive.add("word/\(part)", data: data)
                relationships += """
                <Relationship Id="\(relationshipID)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="\(part)"/>
                """
                body += imageParagraph(
                    number: imageNumber,
                    relationshipID: relationshipID,
                    width: size.width,
                    height: size.height,
                    caption: photo.caption
                )
                if !photo.caption.isEmpty {
                    body += paragraph(photo.caption, style: "Caption")
                }
            }
        }

        try archive.add("word/_rels/document.xml.rels", text: relationships + "</Relationships>")
        try archive.add("word/document.xml", text: """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
                    xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
                    xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
                    xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
                    xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">
          <w:body>
            \(body)
            <w:sectPr>
              <w:pgSz w:w="11906" w:h="16838"/>
              <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"
                       w:header="720" w:footer="720" w:gutter="0"/>
            </w:sectPr>
          </w:body>
        </w:document>
        """)
    }

    private static func dateLabel(_ date: LocalDate) -> String {
        String(format: "%02d.%02d.%04d", date.day, date.month, date.year)
    }

    private static func paragraph(_ text: String, style: String = "Normal", startPage: Bool = false) -> String {
        let pageBreak = startPage ? "<w:pageBreakBefore/>" : ""
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let content = normalized.components(separatedBy: "\n").map { line in
            line.components(separatedBy: "\t").map { word in
                "<w:t xml:space=\"preserve\">\(xmlEscaped(word))</w:t>"
            }.joined(separator: "<w:tab/>")
        }.joined(separator: "<w:br/>")
        return "<w:p><w:pPr><w:pStyle w:val=\"\(style)\"/>\(pageBreak)</w:pPr><w:r>\(content)</w:r></w:p>"
    }

    private static func imageParagraph(
        number: Int,
        relationshipID: String,
        width: Int,
        height: Int,
        caption: String
    ) -> String {
        // Keep both portrait and landscape photos within the printable area of an A4 page.
        let emusPerInch = 914_400.0
        let scale = min(6.2 * emusPerInch / Double(width), 4.5 * emusPerInch / Double(height))
        let cx = max(1, Int(Double(width) * scale))
        let cy = max(1, Int(Double(height) * scale))
        let keepWithCaption = caption.isEmpty ? "" : "<w:keepNext/>"
        let description = xmlEscaped(caption.isEmpty ? "Staj fotoğrafı" : caption)

        return """
        <w:p>
          <w:pPr><w:pStyle w:val="Photo"/>\(keepWithCaption)</w:pPr>
          <w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0">
            <wp:extent cx="\(cx)" cy="\(cy)"/>
            <wp:docPr id="\(number)" name="Fotoğraf \(number)" descr="\(description)"/>
            <wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr>
            <a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">
              <pic:pic>
                <pic:nvPicPr><pic:cNvPr id="\(number)" name="Fotoğraf \(number)"/><pic:cNvPicPr/></pic:nvPicPr>
                <pic:blipFill><a:blip r:embed="\(relationshipID)"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>
                <pic:spPr>
                  <a:xfrm><a:off x="0" y="0"/><a:ext cx="\(cx)" cy="\(cy)"/></a:xfrm>
                  <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
                </pic:spPr>
              </pic:pic>
            </a:graphicData></a:graphic>
          </wp:inline></w:drawing></w:r>
        </w:p>
        """
    }

    private static func xmlEscaped(_ text: String) -> String {
        var escaped = String()
        escaped.reserveCapacity(text.utf8.count)
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x26: escaped += "&amp;"
            case 0x3C: escaped += "&lt;"
            case 0x3E: escaped += "&gt;"
            case 0x22: escaped += "&quot;"
            case 0x27: escaped += "&apos;"
            case 0x09, 0x0A, 0x0D, 0x20...0xD7FF, 0xE000...0xFFFD, 0x10000...0x10FFFF:
                escaped.unicodeScalars.append(scalar)
            default:
                continue
            }
        }
        return escaped
    }

    private static func jpegSize(_ data: Data) -> (width: Int, height: Int)? {
        data.withUnsafeBytes { bytes in
            guard bytes.count >= 4, bytes[0] == 0xFF, bytes[1] == 0xD8,
                  bytes[bytes.count - 2] == 0xFF, bytes[bytes.count - 1] == 0xD9 else { return nil }
            var offset = 2
            // The start-of-frame segment contains the pixel dimensions, before scan data.
            while offset < bytes.count {
                guard bytes[offset] == 0xFF else { return nil }
                while offset < bytes.count, bytes[offset] == 0xFF { offset += 1 }
                guard offset < bytes.count else { return nil }
                let marker = bytes[offset]
                offset += 1
                guard marker != 0xD9, marker != 0xDA, offset + 2 <= bytes.count else { return nil }

                let length = Int(bytes[offset]) * 256 + Int(bytes[offset + 1])
                guard length >= 2, length <= bytes.count - offset else { return nil }
                switch marker {
                case 0xC0...0xC3, 0xC5...0xC7, 0xC9...0xCB, 0xCD...0xCF:
                    guard length >= 8 else { return nil }
                    let height = Int(bytes[offset + 3]) * 256 + Int(bytes[offset + 4])
                    let width = Int(bytes[offset + 5]) * 256 + Int(bytes[offset + 6])
                    guard width > 0, height > 0 else { return nil }
                    return (width, height)
                default:
                    offset += length
                }
            }
            return nil
        }
    }

    private static let contentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Default Extension="jpg" ContentType="image/jpeg"/>
      <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
      <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
    </Types>
    """

    private static let packageRelationships = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
    </Relationships>
    """

    private static let styles = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
      <w:docDefaults><w:rPrDefault><w:rPr>
        <w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="Calibri" w:cs="Calibri"/>
        <w:color w:val="000000"/><w:sz w:val="22"/><w:szCs w:val="22"/><w:lang w:val="tr-TR"/>
      </w:rPr></w:rPrDefault></w:docDefaults>
      <w:style w:type="paragraph" w:default="1" w:styleId="Normal">
        <w:name w:val="Normal"/><w:qFormat/>
        <w:pPr><w:spacing w:after="160" w:line="276" w:lineRule="auto"/></w:pPr>
      </w:style>
      <w:style w:type="paragraph" w:styleId="Title">
        <w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/>
        <w:pPr><w:keepNext/><w:spacing w:after="480"/></w:pPr>
        <w:rPr><w:b/><w:sz w:val="56"/><w:szCs w:val="56"/></w:rPr>
      </w:style>
      <w:style w:type="paragraph" w:styleId="Label">
        <w:name w:val="Bilgi etiketi"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/>
        <w:pPr><w:keepNext/><w:spacing w:before="80" w:after="40"/></w:pPr>
        <w:rPr><w:b/></w:rPr>
      </w:style>
      <w:style w:type="paragraph" w:styleId="Heading1">
        <w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/>
        <w:pPr><w:keepNext/><w:keepLines/><w:spacing w:after="240"/><w:outlineLvl w:val="0"/></w:pPr>
        <w:rPr><w:b/><w:sz w:val="40"/><w:szCs w:val="40"/></w:rPr>
      </w:style>
      <w:style w:type="paragraph" w:styleId="Heading2">
        <w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/>
        <w:pPr><w:keepNext/><w:keepLines/><w:spacing w:before="120" w:after="60"/><w:outlineLvl w:val="1"/></w:pPr>
        <w:rPr><w:b/><w:sz w:val="24"/><w:szCs w:val="24"/></w:rPr>
      </w:style>
      <w:style w:type="paragraph" w:styleId="Photo">
        <w:name w:val="Staj fotoğrafı"/><w:basedOn w:val="Normal"/><w:next w:val="Caption"/>
        <w:pPr><w:spacing w:before="80" w:after="80"/><w:jc w:val="center"/></w:pPr>
      </w:style>
      <w:style w:type="paragraph" w:styleId="Caption">
        <w:name w:val="caption"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/>
        <w:pPr><w:spacing w:after="220"/><w:jc w:val="center"/></w:pPr>
        <w:rPr><w:i/><w:sz w:val="20"/><w:szCs w:val="20"/></w:rPr>
      </w:style>
    </w:styles>
    """
}
