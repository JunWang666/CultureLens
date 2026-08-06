import Foundation
import SwiftUI

/// User-facing content language for UI chrome and LLM output.
nonisolated enum AppLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
  case zhHans = "zh-Hans"
  case english = "en"

  var id: String { rawValue }

  /// BCP-47 tag used by `Locale` and prompt instructions.
  var localeIdentifier: String { rawValue }

  var locale: Locale { Locale(identifier: localeIdentifier) }

  var displayName: String {
    switch self {
    case .zhHans:
      String(localized: "简体中文")
    case .english:
      String(localized: "English")
    }
  }

  /// Native name shown in the language picker (not itself localized away).
  var nativeDisplayName: String {
    switch self {
    case .zhHans: "简体中文"
    case .english: "English"
    }
  }

  /// Knowledge-pack source language today; overlays may add others later.
  static let knowledgeSource: AppLanguage = .zhHans

  var isKnowledgeSource: Bool { self == .knowledgeSource }

  /// Prompt-facing English name of the language.
  var promptLanguageName: String {
    switch self {
    case .zhHans: "Simplified Chinese"
    case .english: "English"
    }
  }
}

/// Persisted language preference. `.system` follows the device locale.
nonisolated enum AppLanguagePreference: String, CaseIterable, Identifiable, Codable, Sendable {
  case system
  case zhHans = "zh-Hans"
  case english = "en"

  var id: String { rawValue }

  func resolved(deviceLocale: Locale = .autoupdatingCurrent) -> AppLanguage {
    switch self {
    case .zhHans:
      return .zhHans
    case .english:
      return .english
    case .system:
      if let code = deviceLocale.language.languageCode?.identifier.lowercased(),
        code.hasPrefix("zh")
      {
        return .zhHans
      }
      let identifier = deviceLocale.identifier.lowercased()
      if identifier.hasPrefix("zh") || identifier.contains("-zh") || identifier.contains("_zh")
      {
        return .zhHans
      }
      return .english
    }
  }
}

/// Observable store for the app content language.
@Observable
@MainActor
final class AppLanguageStore {
  nonisolated static let preferenceKey = "culturelens.appLanguagePreference"

  var preference: AppLanguagePreference {
    didSet {
      UserDefaults.standard.set(preference.rawValue, forKey: Self.preferenceKey)
    }
  }

  var language: AppLanguage {
    preference.resolved()
  }

  var locale: Locale { language.locale }

  init(
    preference: AppLanguagePreference = AppLanguageStore.loadPreference()
  ) {
    self.preference = preference
  }

  /// Safe to call from default arguments and other nonisolated contexts.
  nonisolated static func loadPreference() -> AppLanguagePreference {
    guard let raw = UserDefaults.standard.string(forKey: preferenceKey),
      let value = AppLanguagePreference(rawValue: raw)
    else {
      return .system
    }
    return value
  }

  /// Non-isolated read for services that cannot hop to the main actor.
  nonisolated static func currentLanguage() -> AppLanguage {
    let raw = UserDefaults.standard.string(forKey: preferenceKey)
    let preference = raw.flatMap(AppLanguagePreference.init(rawValue:)) ?? .system
    return preference.resolved(deviceLocale: .autoupdatingCurrent)
  }
}
