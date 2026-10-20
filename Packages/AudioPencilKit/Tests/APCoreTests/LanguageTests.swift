import APCore
import Foundation
import Testing

struct LanguageTests {
    @Test func defaultsAreEnglishPlusTheMacsLanguages() {
        #expect(SpokenLanguage.defaultCodes(preferred: ["fr-CA", "en-GB", "nb-NO", "tlh"]) == ["en", "fr", "no"])
        #expect(SpokenLanguage.whisperCodes.count == 100)
        #expect(SpokenLanguage(code: "fr").englishName == "French")
        #expect(SpokenLanguage(code: "FR").badge == "FR")
    }

    @Test func memoryIsPerAppThenLastUsedThenEnglish() {
        var memory = LanguageMemory()
        #expect(memory.language(forApp: "com.apple.mail") == .english)
        memory.remember(SpokenLanguage(code: "fr"), forApp: "com.apple.mail")
        memory.remember(.english, forApp: "com.apple.dt.Xcode")
        #expect(memory.language(forApp: "com.apple.mail").code == "fr")
        #expect(memory.language(forApp: "com.apple.dt.Xcode") == .english)
        #expect(memory.language(forApp: "md.obsidian") == .english) // last used anywhere
        memory.forget(app: "com.apple.mail")
        #expect(memory.language(forApp: "com.apple.mail") == .english)
    }

    @Test func englishUsesTheEnglishModelOthersTheMultilingualOne() {
        var settings = DictationSettings()
        #expect(settings.transcriptionVariant(for: .english) == "openai_whisper-small.en")
        #expect(settings.transcriptionVariant(for: SpokenLanguage(code: "fr")) == "openai_whisper-large-v3-v20240930_turbo_632MB")
        settings.transcriptionModel = "openai_whisper-large-v3-v20240930_turbo_632MB" // multilingual for English too
        #expect(settings.transcriptionVariant(for: SpokenLanguage(code: "fr")) == "openai_whisper-large-v3-v20240930_turbo_632MB")
    }

    @Test func vocabularyIsGlobalPlusThatLanguage() {
        var settings = DictationSettings()
        settings.customVocabulary = ["Nextcloud", "Adobe"]
        settings.languageVocabulary = ["fr": ["Loïc-William", "Adobe"]]
        #expect(settings.vocabulary(for: SpokenLanguage(code: "fr")) == ["Nextcloud", "Adobe", "Loïc-William"])
        #expect(settings.vocabulary(for: .english) == ["Nextcloud", "Adobe"])
    }

    @Test func offeredLanguagesIncludeTheCurrentOne() {
        var settings = DictationSettings()
        settings.dictationLanguages = ["en", "es"]
        #expect(settings.offeredLanguages(including: SpokenLanguage(code: "de")).map(\.code) == ["en", "es", "de"])
    }

    @Test func promptsAskForTheSpokenLanguage() {
        let french = PromptBuilder.prompt(for: .polished, transcript: "Bonjour", context: .quick, language: SpokenLanguage(code: "fr"))
        #expect(french.instructions.contains("Write in French; never translate."))
        let english = PromptBuilder.prompt(for: .polished, transcript: "Hello", context: .quick)
        #expect(!english.instructions.contains("never translate"))
        #expect(PromptBuilder.titleAndTagsPrompt(text: "x", knownTags: [], language: SpokenLanguage(code: "es")).instructions.contains("Spanish"))
    }

    @Test func longFormSectionsAskForTranslatedHeadings() {
        let french = PromptBuilder.prompt(for: .professional, transcript: "Bonjour", context: .longForm, language: SpokenLanguage(code: "fr"))
        #expect(french.input.contains("headings included, in French."))
        let english = PromptBuilder.prompt(for: .professional, transcript: "Hello", context: .longForm)
        #expect(!english.input.contains("headings included"))
    }

    @Test func tagsKeepAccentedLetters() {
        #expect(TitleAndTags.normaliseTag("#Été 2026") == "été-2026")
        #expect(TitleAndTags.normaliseTag("Año Nuevo") == "año-nuevo")
    }

    @Test func cleanerDropsFrenchAndSpanishPreambles() {
        #expect(OutputCleaner.clean("Voici le texte corrigé :\nBonne journée.") == "Bonne journée.")
        #expect(OutputCleaner.clean("Aquí está el texto:\nBuen día.") == "Buen día.")
    }

    @Test func likeMePrefersSamplesInTheSpokenLanguage() {
        let english = WritingSample(id: "en", kind: "work-email", text: "The project is running late because the supplier missed the deadline.")
        let french = WritingSample(id: "fr", kind: "diary", text: "Journée calme, un peu de jardinage et une longue promenade.", language: "fr")
        let picked = WritingSampleSelector.pick(for: "The project is late", from: [english, french], language: SpokenLanguage(code: "fr"), limit: 1)
        #expect(picked.map(\.id) == ["fr"])
        let both = WritingSampleSelector.pick(for: "The project is late", from: [english, french], language: SpokenLanguage(code: "fr"), limit: 2)
        #expect(both.map(\.id) == ["fr", "en"]) // others fill the gap
    }

}

struct HotkeySettingsTests {
    @Test func aTapStartIsStoppedWithATap() {
        var settings = DictationSettings()
        settings.stopGesture = .doubleTapFn
        #expect(settings.effectiveStopGesture == .doubleTapFn)
        settings.startGesture = .singleTap
        #expect(settings.effectiveStopGesture == .singleTapFn)
    }

    @Test func labelsFollowTheKey() {
        #expect(StartGesture.doubleTap.label(.fn) == "Double-tap Fn")
        #expect(StopGesture.singleTapFn.label(.rightOption) == "Tap Right ⌥")
        #expect(KeyShortcut.controlOptionSpace.modifierSymbols == "⌃⌥")
    }

    @Test func oldSettingsKeepTheirHotkey() throws {
        let old = #"{"stopGesture":"doubleTapFn","fallbackShortcutEnabled":true}"#
        let settings = try JSONDecoder().decode(DictationSettings.self, from: Data(old.utf8))
        #expect(settings.gestureKey == .fn && settings.startGesture == .doubleTap)
        #expect(settings.fallbackShortcut == .controlOptionSpace && settings.stopGesture == .doubleTapFn)
    }
}

