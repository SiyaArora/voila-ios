//
//  OutfitAnalyzer.swift
//  voila
//
//  Analyzes an outfit photo fully on-device:
//   1. Apple's Vision framework extracts visual signals (what's in the photo +
//      an aesthetics score), since Apple Intelligence's on-device language model
//      is text-only and can't read images directly.
//   2. Those signals are turned into text and handed to the Foundation Models
//      framework (Apple Intelligence) to produce a rating and styling feedback.
//

import Foundation
import CoreGraphics
import ImageIO
import Vision
import FoundationModels

/// The structured result Apple Intelligence generates for an outfit.
@Generable(description: "A fashion rating and styling feedback for an outfit photo")
struct OutfitRating {
    @Guide(description: "An overall style rating from 1 (poor) to 10 (excellent)", .range(1...10))
    var rating: Int

    @Guide(description: "Two to four short sentences: what works about the outfit, and one or two concrete things to add or change to elevate the look")
    var feedback: String
}

/// Visual signals the Vision framework extracts from a photo.
private struct OutfitSignals {
    /// The most confident classification labels Vision detected (e.g. "jacket", "denim").
    var labels: [String]
    /// The dominant clothing colors, most prominent first (e.g. "charcoal", "cream").
    var colors: [String]
    /// Overall aesthetics score in the range -1 (least desirable) to 1 (most desirable).
    var aestheticsScore: Float
}

struct OutfitAnalyzer {

    enum AnalyzerError: LocalizedError {
        case appleIntelligenceUnavailable
        case generationFailed(String)

        var errorDescription: String? {
            switch self {
            case .appleIntelligenceUnavailable:
                return "Apple Intelligence isn't available. Turn it on in Settings on a supported device to use Voilà."
            case .generationFailed(let detail):
                return "Couldn't analyze the outfit: \(detail)"
            }
        }
    }

    /// Analyzes an outfit photo and returns a rating with feedback.
    func analyze(_ image: CGImage, orientation: CGImagePropertyOrientation) async throws -> OutfitRating {
        // Apple Intelligence must be available before we prompt the model.
        guard case .available = SystemLanguageModel.default.availability else {
            throw AnalyzerError.appleIntelligenceUnavailable
        }

        let signals = try await extractSignals(from: image, orientation: orientation)

        print("PROMPT[analyze]: \(await PromptConfig.shared.instructions())")
        let session = LanguageModelSession(instructions: await PromptConfig.shared.instructions())
        do {
            let response = try await session.respond(
                to: Self.prompt(for: signals),
                generating: OutfitRating.self
            )
            return response.content
        } catch {
            throw AnalyzerError.generationFailed(error.localizedDescription)
        }
    }

    // MARK: - Vision

    /// Runs Vision's image-classification and aesthetics requests on the photo.
    private func extractSignals(
        from image: CGImage,
        orientation: CGImagePropertyOrientation
    ) async throws -> OutfitSignals {
        // Top classification labels, filtered for a sensible confidence balance.
        let classifyRequest = ClassifyImageRequest()
        let labels = try await classifyRequest.perform(on: image, orientation: orientation)
            .filter { $0.hasMinimumPrecision(0.1, forRecall: 0.8) }
            .sorted { $0.confidence > $1.confidence }
            .prefix(8)
            .map(\.identifier)

        // An overall aesthetics score for the photo.
        let aestheticsRequest = CalculateImageAestheticsScoresRequest()
        let aesthetics = try await aestheticsRequest.perform(on: image, orientation: orientation)

        // The dominant clothing colors, so the model can be specific about color.
        let colors = await ColorAnalyzer().dominantColors(in: image, orientation: orientation)

        return OutfitSignals(
            labels: Array(labels),
            colors: colors,
            aestheticsScore: aesthetics.overallScore
        )
    }

    // MARK: - Prompting

    /// The offline fallback. `PromptConfig` prefers the server's copy, but this
    /// is what the app uses when the server has never been reached.
    static let instructions = """
    You are Voilà, a calm, honest AI fashion stylist with minimalist taste. \
    You rate outfits and give concise, encouraging, concrete styling feedback. \
    Always give a rating from 1 to 10 and 2-4 short sentences that name the \
    outfit's specific colors: comment on how the color palette works together, \
    what the person is doing right, and one or two concrete additions or changes \
    (a color, layer, or piece) that would elevate the look. Keep the tone warm \
    and grounded, never harsh.
    """

    private static func prompt(for signals: OutfitSignals) -> String {
        let detected = signals.labels.isEmpty
            ? "no distinct elements"
            : signals.labels.joined(separator: ", ")

        let colors = signals.colors.isEmpty
            ? "the colors couldn't be determined"
            : signals.colors.joined(separator: ", ")

        // Map the -1...1 aesthetics score to a short qualitative phrase for the model.
        let quality: String
        switch signals.aestheticsScore {
        case ..<(-0.3): quality = "low"
        case ..<0.3:    quality = "moderate"
        default:        quality = "high"
        }

        return """
        An on-device vision analysis looked at a photo of someone's outfit.
        - Dominant clothing colors (most prominent first): \(colors).
        - Detected elements: \(detected).
        - Overall photo visual appeal: \(quality) (\(String(format: "%.2f", signals.aestheticsScore)) on a -1 to 1 scale).

        These signals are approximate and don't capture fit or fine styling \
        detail, so treat them as hints. Base your feedback on the colors above and \
        refer to them by name. Rate the outfit and give styling feedback.
        """
    }
}
