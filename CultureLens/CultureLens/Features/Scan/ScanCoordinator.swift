import Foundation
import Observation

nonisolated enum ScanLocationSource: Sendable {
    case currentDevice
    case photoMetadata(PlaceContext?)
    case none
}

@MainActor
@Observable
final class ScanCoordinator {
    private static let focusAnnotationNote =
        "图片中的朱红色矩形框由应用添加，用来标记用户要识别的目标。请只识别框内对象，并使用框外完整画面理解场景、尺度和相邻结构。"

    enum Phase {
        case idle
        case preparing
        case locating
        case recognizing
        case failed(String)

        var message: String {
            switch self {
            case .idle: String(localized: "准备扫描")
            case .preparing: String(localized: "正在保护隐私并整理图片…")
            case .locating: String(localized: "正在获取当前位置…")
            case .recognizing: String(localized: "正在辨认文化线索…")
            case .failed(let message): message
            }
        }

        var isWorking: Bool {
            switch self {
            case .preparing, .locating, .recognizing: true
            case .idle, .failed: false
            }
        }
    }

    private(set) var phase: Phase = .idle
    private(set) var locationNotice: String?
    private var task: Task<Void, Never>?
    private let locationProvider: LocationContextProvider

    init(locationProvider: LocationContextProvider? = nil) {
        self.locationProvider = locationProvider ?? LocationContextProvider()
    }

    func begin(
        normalizedImageData: Data,
        focusRegion: NormalizedImageRegion?,
        locationSource: ScanLocationSource,
        contextNote: String,
        userKnowledgeStates: [UserKnowledgeStateContext] = [],
        service: RecognitionService,
        onSuccess: @escaping @MainActor @Sendable (ScanSession) -> Void
    ) {
        cancel()
        phase = .preparing
        locationNotice = nil

        task = Task {
            do {
                let recognitionImageData = try await Task.detached(priority: .userInitiated) {
                    guard let focusRegion else { return normalizedImageData }
                    return try ImagePreprocessor.annotatedJPEG(
                        from: normalizedImageData,
                        region: focusRegion
                    )
                }.value

                try Task.checkCancellation()

                let place: PlaceContext?
                switch locationSource {
                case .currentDevice:
                    phase = .locating
                    do {
                        place = try await locationProvider.requestBestPlace()
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        place = nil
                        locationNotice = error.localizedDescription
                    }
                case .photoMetadata(let recordedPlace):
                    place = recordedPlace
                    locationNotice = recordedPlace == nil
                        ? String(localized: "照片未记录地理信息，将只根据图片识别。")
                        : String(localized: "将使用照片记录的位置。")
                case .none:
                    place = nil
                }

                try Task.checkCancellation()
                phase = .recognizing

                let input = RecognitionInput(
                    imageData: recognitionImageData,
                    place: place,
                    contextNote: recognitionContextNote(
                        contextNote,
                        hasFocusAnnotation: focusRegion != nil
                    ),
                    localeIdentifier: AppLanguageStore.currentLanguage().localeIdentifier,
                    userKnowledgeStates: userKnowledgeStates
                )
                let result = try await service.recognize(input)

                try Task.checkCancellation()
                let session = ScanSession(
                    id: result.id,
                    imageData: recognitionImageData,
                    result: result,
                    place: place,
                    createdAt: Date(),
                    isDemo: service.mode == .demo
                )
                phase = .idle
                onSuccess(session)
            } catch is CancellationError {
                phase = .idle
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        phase = .idle
    }

    func resetFailure() {
        if case .failed = phase {
            phase = .idle
        }
    }

    func showFailure(_ message: String) {
        phase = .failed(message)
    }

    private func recognitionContextNote(
        _ contextNote: String,
        hasFocusAnnotation: Bool
    ) -> String {
        let trimmedNote = contextNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hasFocusAnnotation else { return trimmedNote }
        guard !trimmedNote.isEmpty else { return Self.focusAnnotationNote }
        return Self.focusAnnotationNote + "\n" + trimmedNote
    }
}
