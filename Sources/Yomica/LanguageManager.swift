import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"
    case japanese = "ja"
    case cantonese = "zh-HK" // Cantonese commonly uses zh-HK or yue
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        case .english: return "English"
        case .japanese: return "日本語"
        case .cantonese: return "粵語"
        }
    }
    
    var locale: Locale {
        Locale(identifier: self.rawValue)
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system = "系统"
    case light = "浅色"
    case dark = "深色"
    
    var id: String { self.rawValue }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
    
    var displayName: String {
        switch self {
        case .system: return "系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}

enum LibraryDisplayMode: String, CaseIterable, Identifiable {
    case standard = "默认"
    case coverFocused = "封面优先"
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .standard: return "默认"
        case .coverFocused: return "封面优先"
        }
    }
}
