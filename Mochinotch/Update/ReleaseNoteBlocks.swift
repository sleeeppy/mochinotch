import Foundation

/// 릴리즈 본문(마크다운)을 패치 노트 화면에서 그릴 덩어리로 나눈다.
/// 제목, 문단, 목록만 남긴다. 표(파일 해시 등), 그림, HTML 주석은 노치에서 읽을 것이 아니라 뺀다.
/// 굵게, 코드, 링크 같은 줄 안 표시는 그대로 두고 화면에서 그린다.
enum ReleaseNoteBlock: Equatable {
    case heading(String)
    case paragraph(String)
    case bullet(String)

    static func parse(_ markdown: String) -> [ReleaseNoteBlock] {
        var text = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        text = text.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "!\\[[^\\]]*\\]\\([^)]*\\)", with: "", options: .regularExpression)

        var blocks: [ReleaseNoteBlock] = []
        var paragraph: [String] = []
        var bullet: String?

        func flush() {
            if let current = bullet {
                blocks.append(.bullet(current))
                bullet = nil
            }
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph.removeAll()
            }
        }

        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flush()
                continue
            }
            if line.hasPrefix("|") || line.hasPrefix("---") || line.hasPrefix("***") || line.hasPrefix("```") {
                flush()
                continue
            }
            if let heading = line.firstMatch(of: /^#{1,6}\s+(.+)$/) {
                flush()
                blocks.append(.heading(String(heading.1).trimmingCharacters(in: CharacterSet(charactersIn: "# "))))
                continue
            }
            if let item = line.firstMatch(of: /^(?:[-*+]|\d+[.)])\s+(.+)$/) {
                flush()
                bullet = String(item.1)
                continue
            }
            // 목록 바로 아래에 들여 쓴 줄은 그 항목에 잇는다.
            if let current = bullet, raw.first == " " || raw.first == "\t" {
                bullet = current + " " + line
                continue
            }
            if bullet != nil { flush() }
            paragraph.append(line)
        }
        flush()
        return blocks
    }
}
