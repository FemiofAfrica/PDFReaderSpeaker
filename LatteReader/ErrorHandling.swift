import Foundation
import SwiftUI

/// User-friendly error messages with actionable recommendations
struct UserFacingError: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let actions: [ErrorAction]
}

struct ErrorAction: Identifiable {
    let id = UUID()
    let label: String
    let action: () -> Void
}

@MainActor
final class ErrorHandler: ObservableObject {
    @Published var currentError: UserFacingError?
    
    func handleVoiceEngineError(engine: VoiceEngine, availability: VoiceEngineAvailability, onSwitchToSystem: @escaping () -> Void) {
        guard !availability.isAvailable else { return }
        
        let title: String
        let message: String
        var actions: [ErrorAction] = []
        
        switch engine {
        case .kokoro:
            title = "Kokoro Voice Unavailable"
            message = availability.message
            actions.append(ErrorAction(label: "Use Piper Fallback", action: {
                // Switch to Piper will be handled by the closure
                self.currentError = nil
            }))
            actions.append(ErrorAction(label: "Use System Voice", action: {
                onSwitchToSystem()
                self.currentError = nil
            }))
            
        case .piper:
            title = "Piper Voice Unavailable"
            message = availability.message
            actions.append(ErrorAction(label: "Use System Voice", action: {
                onSwitchToSystem()
                self.currentError = nil
            }))
        }
        
        actions.append(ErrorAction(label: "Dismiss", action: {
            self.currentError = nil
        }))
        
        currentError = UserFacingError(title: title, message: message, actions: actions)
    }
    
    func handlePDFError(_ error: PDFReaderError) {
        let title: String
        let message: String
        let actions: [ErrorAction]
        
        switch error {
        case .cannotOpen:
            title = "Cannot Open PDF"
            message = "This PDF file could not be opened. It may be corrupted or use an unsupported format."
            actions = [ErrorAction(label: "OK", action: { self.currentError = nil })]
            
        case .noExtractableText:
            title = "No Text Found"
            message = "This PDF contains no selectable text. It may be a scanned document that requires OCR (Optical Character Recognition) before it can be read aloud."
            actions = [
                ErrorAction(label: "Learn About OCR", action: {
                    if let url = URL(string: "https://support.apple.com/guide/preview/extract-text-from-an-image-or-pdf-prvw625a5b2c/mac") {
                        NSWorkspace.shared.open(url)
                    }
                    self.currentError = nil
                }),
                ErrorAction(label: "OK", action: { self.currentError = nil })
            ]
            
        case .liteparseFailed(let details):
            title = "Text Extraction Failed"
            message = "Failed to extract text from this PDF: \(details)"
            actions = [ErrorAction(label: "OK", action: { self.currentError = nil })]
        }
        
        currentError = UserFacingError(title: title, message: message, actions: actions)
    }
    
    func dismiss() {
        currentError = nil
    }
}

/// SwiftUI view modifier to display error alerts
struct ErrorAlertModifier: ViewModifier {
    @ObservedObject var errorHandler: ErrorHandler
    
    func body(content: Content) -> some View {
        content.alert(item: $errorHandler.currentError) { error in
            Alert(
                title: Text(error.title),
                message: Text(error.message),
                primaryButton: error.actions.first.map { action in
                    .default(Text(action.label), action: action.action)
                } ?? .default(Text("OK"), action: { errorHandler.dismiss() }),
                secondaryButton: error.actions.dropFirst().first.map { action in
                    .default(Text(action.label), action: action.action)
                } ?? .cancel()
            )
        }
    }
}

extension View {
    func errorAlert(errorHandler: ErrorHandler) -> some View {
        modifier(ErrorAlertModifier(errorHandler: errorHandler))
    }
}
