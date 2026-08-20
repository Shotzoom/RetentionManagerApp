//
//  TranslationService.swift
//  RetentionManager
//
//  Created by John Hawley on 3/11/26.
//

import Foundation
import FoundationModels

/// Service for translating retention message text using FoundationModels
class TranslationService {
    static let shared = TranslationService()
    
    private let model = SystemLanguageModel.default
    
    private init() {}
    
    /// Translation result structure
    @Generable
    struct TranslationResult {
        @Guide(description: "The translated text in Spanish")
        let spanish: String
        
        @Guide(description: "The translated text in French")
        let french: String
        
        @Guide(description: "The translated text in German")
        let german: String
    }
    
    /// Translate text to all supported languages
    func translateText(_ text: String) async throws -> TranslationResult {
        // Check if model is available
        guard case .available = model.availability else {
            throw TranslationError.modelUnavailable
        }
        
        let instructions = """
        You are a professional translator for business subscription retention messages for a golf application. 
        Translate the given text accurately to Spanish, French, and German.
        Maintain the tone and meaning of the original text. Keep translations concise and natural.
        This is legitimate business communication for subscription management.
        
        Context: This is for TOUR Caddie, a golf GPS and statistics app. Common golf terms should be 
        translated appropriately (e.g., caddie, scorecard, handicap, course, round, tee, green, etc.).
        Keep the app name "TOUR Caddie" unchanged in all translations.
        """
        
        let session = LanguageModelSession(instructions: instructions)
        
        let prompt = """
        Translate this golf app subscription retention message:
        "\(text)"
        
        Provide translations for:
        - Spanish (es)
        - French (fr)
        - German (de)
        
        Context: This is a legitimate business message shown to users about their TOUR Caddie golf app subscription.
        Preserve golf-specific terminology appropriately for each language.
        """
        
        do {
            let response = try await session.respond(
                generating: TranslationResult.self,
                includeSchemaInPrompt: true
            ) {
                Prompt(prompt)
            }
            
            return response.content
        } catch {
            // Check if this is a safety guardrail error
            if error.localizedDescription.contains("Safety guardrails") || 
               error.localizedDescription.contains("guardrails") {
                print("⚠️ Safety guardrails triggered for translation")
                print("📝 Original text: \(text)")
                throw TranslationError.safetyGuardrailsTriggered
            }
            throw error
        }
    }
    
    /// Translate header and body text separately
    func translateMessage(header: String, body: String) async throws -> (header: TranslationResult, body: TranslationResult) {
        async let headerTranslation = translateText(header)
        async let bodyTranslation = translateText(body)
        
        return try await (header: headerTranslation, body: bodyTranslation)
    }
}

// MARK: - Error Types

enum TranslationError: LocalizedError {
    case modelUnavailable
    case safetyGuardrailsTriggered
    
    var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            return "Translation model is not available. Please ensure Apple Intelligence is enabled on this device."
        case .safetyGuardrailsTriggered:
            return "Apple's safety system blocked the translation. The content may have been flagged as inappropriate. Try rephrasing your message text or translate manually. This is a limitation of Apple's on-device AI model."
        }
    }
}
