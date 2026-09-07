//
//  ContentView.swift
//  voila
//
//  Created by Siya Arora on 6/30/26.
//

import SwiftUI
import PhotosUI
import ImageIO
import FoundationModels

struct ContentView: View {
    @State private var selectedItem: PhotosPickerItem?
    @State private var image: CGImage?
    @State private var orientation: CGImagePropertyOrientation = .up
    @State private var rating: Int?
    @State private var feedback: String = ""
    @State private var isAnalyzing = false
    @State private var errorMessage: String = ""

    private let analyzer = OutfitAnalyzer()
    private let model = SystemLanguageModel.default

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header

                if let message = unavailableMessage {
                    banner(message)
                }

                uploadButton

                if let image {
                    Image(image, scale: 1, orientation: displayOrientation, label: Text("Selected outfit"))
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Self.border, lineWidth: 1)
                        )

                    analyzeButton
                }

                if rating != nil || !feedback.isEmpty {
                    resultCard
                }

                if !errorMessage.isEmpty {
                    Text("⚠️ \(errorMessage)")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .background(Self.background.ignoresSafeArea())
        .onChange(of: selectedItem) { _, newItem in
            loadImage(from: newItem)
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 8) {
            Text("Voilà")
                .font(.system(size: 34, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(Self.ink)
            Text("Snap your outfit and get an honest rating, what's working, and a few ways to elevate the look.")
                .font(.subheadline)
                .foregroundStyle(Self.muted)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 12)
    }

    private var uploadButton: some View {
        PhotosPicker(selection: $selectedItem, matching: .images) {
            Text(image == nil ? "Upload outfit photo" : "Choose a different photo")
                .font(.callout.weight(.medium))
                .foregroundStyle(Self.ink)
                .padding(.vertical, 14)
                .padding(.horizontal, 24)
                .frame(maxWidth: 280)
                .background(Self.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Self.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var analyzeButton: some View {
        Button(action: analyze) {
            Text(isAnalyzing ? "Analyzing…" : "Analyze outfit")
                .font(.callout.weight(.semibold))
                .foregroundStyle(Self.card)
                .padding(.vertical, 14)
                .frame(maxWidth: 280)
                .background(Self.ink)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(isAnalyzing)
        .opacity(isAnalyzing ? 0.6 : 1)
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let rating {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(rating)")
                        .font(.system(size: 40, weight: .semibold, design: .serif))
                        .foregroundStyle(Self.ink)
                    Text("/ 10")
                        .font(.title3)
                        .foregroundStyle(Self.muted)
                }
            }

            if !feedback.isEmpty {
                Text(feedback)
                    .font(.body)
                    .foregroundStyle(Self.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Self.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Self.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func banner(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(Self.muted)
            .multilineTextAlignment(.center)
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(Self.card)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Self.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Actions

    private func loadImage(from item: PhotosPickerItem?) {
        rating = nil
        feedback = ""
        errorMessage = ""
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                errorMessage = "That photo couldn't be loaded. Try another."
                return
            }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let rawOrientation = (properties?[kCGImagePropertyOrientation] as? UInt32) ?? 1
            image = cgImage
            orientation = CGImagePropertyOrientation(rawValue: rawOrientation) ?? .up
        }
    }

    private func analyze() {
        guard let image else { return }
        isAnalyzing = true
        errorMessage = ""
        rating = nil
        feedback = ""
        let captured = image
        let capturedOrientation = orientation
        Task {
            do {
                let result = try await analyzer.analyze(captured, orientation: capturedOrientation)
                rating = result.rating
                feedback = result.feedback
            } catch {
                errorMessage = error.localizedDescription
            }
            isAnalyzing = false
        }
    }

    /// A friendly explanation when Apple Intelligence isn't ready, or `nil` when it is.
    private var unavailableMessage: String? {
        switch model.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "This device doesn't support Apple Intelligence, which Voilà uses to rate outfits."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in Settings to start rating outfits."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence is getting ready. This can take a few minutes after enabling it."
        case .unavailable:
            return "Apple Intelligence is currently unavailable."
        }
    }

    /// Bridges the photo's EXIF orientation to the orientation SwiftUI's `Image` expects.
    private var displayOrientation: Image.Orientation {
        switch orientation {
        case .up:            return .up
        case .upMirrored:    return .upMirrored
        case .down:          return .down
        case .downMirrored:  return .downMirrored
        case .left:          return .left
        case .leftMirrored:  return .leftMirrored
        case .right:         return .right
        case .rightMirrored: return .rightMirrored
        @unknown default:    return .up
        }
    }

    // MARK: - Palette

    private static let background = Color(red: 246 / 255, green: 241 / 255, blue: 231 / 255)
    private static let card = Color(red: 251 / 255, green: 248 / 255, blue: 241 / 255)
    private static let ink = Color(red: 44 / 255, green: 39 / 255, blue: 34 / 255)
    private static let muted = Color(red: 138 / 255, green: 130 / 255, blue: 118 / 255)
    private static let border = Color(red: 230 / 255, green: 223 / 255, blue: 209 / 255)
}

#Preview {
    ContentView()
}
