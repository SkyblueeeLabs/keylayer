// 自动生成 — 请勿手动编辑
// 来源: ui/tokens.json
// 重新生成: npm run spec
// spec-hash: c44150cfb3a7

import SwiftUI

enum Tokens {
    static let panelWidth: CGFloat = 320
    static let panelPadding: CGFloat = 16
    static let panelRadius: CGFloat = 14
    static let gap: CGFloat = 12
    static let rowGap: CGFloat = 8
    static let capGap: CGFloat = 6
    static let capWidth: CGFloat = 58
    static let capKeyWidth: CGFloat = 40
    static let capHeight: CGFloat = 26
    static let capRadius: CGFloat = 5
    static let dotSize: CGFloat = 8
    static let titleSize: CGFloat = 15
    static let bodySize: CGFloat = 13
    static let captionSize: CGFloat = 12
    static let microSize: CGFloat = 11
    static let ink = Color(red: 0.173, green: 0.173, blue: 0.165)
    static let muted = Color(red: 0.373, green: 0.369, blue: 0.353)
    static let edge = Color(red: 0.827, green: 0.820, blue: 0.780)
    static let statusOK = Color(red: 0.059, green: 0.431, blue: 0.337)
    static let statusWarn = Color(red: 0.729, green: 0.459, blue: 0.090)
    static let direction = Color(red: 0.094, green: 0.373, blue: 0.647)
    static let directionSoft = Color(red: 0.902, green: 0.945, blue: 0.984)
    static let action = Color(red: 0.729, green: 0.459, blue: 0.090)
    static let actionSoft = Color(red: 0.980, green: 0.933, blue: 0.855)
    static let scroll = Color(red: 0.059, green: 0.431, blue: 0.337)
    static let scrollSoft = Color(red: 0.882, green: 0.961, blue: 0.933)
    static let modifier = Color(red: 0.325, green: 0.290, blue: 0.718)
    static let modifierSoft = Color(red: 0.933, green: 0.929, blue: 0.996)

    static func groupAccent(_ group: String) -> Color {
        switch group {
        case "direction": return direction
        case "action": return action
        case "scroll": return scroll
        case "modifier": return modifier
        default: return ink
        }
    }

    static func groupSoft(_ group: String) -> Color {
        switch group {
        case "direction": return directionSoft
        case "action": return actionSoft
        case "scroll": return scrollSoft
        case "modifier": return modifierSoft
        default: return ink
        }
    }
}
