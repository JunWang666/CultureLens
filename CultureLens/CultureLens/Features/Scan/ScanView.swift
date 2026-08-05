import PhotosUI
import SwiftUI

struct ScanView: View {
    let onRecognized: @MainActor @Sendable (ScanSession) -> Void

    @Environment(\.recognitionService) private var recognitionService
    @Environment(KnowledgeProgressStore.self) private var knowledgeProgressStore
    @State private var coordinator = ScanCoordinator()
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var lastScanInput: LastScanInput?
    @State private var useLocation = !ProcessInfo.processInfo.arguments.contains("-UITesting")
    @State private var captureRequestID: UUID?
    @State private var isCameraAvailable = CameraCaptureView.isCameraAvailable
    @State private var isTorchOn = false
    @State private var helpSheetPresented = false
    @State private var pendingReview: PendingScanImage?
    @State private var preparedReview: PreparedReviewImage?
    /// `nil` until the user draws a selection; sending with no selection
    /// just sends the whole photo (same as "直接发送").
    @State private var focusSelection: NormalizedImageRegion?
    @State private var reviewPrepareError: String?
    @State private var previewPlace: PlaceContext?
    @State private var isResolvingPreviewPlace = false
    @State private var locationProvider = LocationContextProvider()

    private var isReviewing: Bool {
        pendingReview != nil
    }

    var body: some View {
        ZStack {
            cameraBackdrop

            CameraCaptureView(
                captureRequestID: captureRequestID,
                isTorchOn: isTorchOn,
                onAvailabilityChanged: { @MainActor @Sendable isAvailable in
                    isCameraAvailable = isAvailable
                },
                onTorchStateChanged: { @MainActor @Sendable torchIsOn in
                    isTorchOn = torchIsOn
                },
                completion: { @MainActor @Sendable data in
                    handleCapturedPhoto(data)
                }
            )
            .opacity(isCameraAvailable && !isReviewing ? 1 : 0)
            .allowsHitTesting(!isReviewing)
            .ignoresSafeArea()

            if let preparedReview {
                CaptureReviewLayer(
                    imageID: preparedReview.id,
                    imageData: preparedReview.data,
                    imagePixelSize: preparedReview.pixelSize,
                    selection: $focusSelection
                )
            } else if isReviewing {
                Color.black.opacity(0.72)
                    .ignoresSafeArea()
                ProgressView("正在准备图片…")
                    .tint(.white)
                    .foregroundStyle(.white)
            } else {
                viewfinder
            }

            VStack {
                if showsLocationPreview {
                    HStack {
                        Spacer(minLength: 0)
                        ScanLocationPreviewButton(
                            place: previewPlace,
                            isLoading: isResolvingPreviewPlace
                        )
                        .accessibilityIdentifier("scan.locationPreview")
                    }
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Spacer()

                if let reviewPrepareError, isReviewing {
                    reviewErrorCard(reviewPrepareError)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if coordinator.phase.isWorking {
                    progressCard
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if case .failed(let message) = coordinator.phase {
                    errorCard(message)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if isReviewing, !coordinator.phase.isWorking {
                    if case .failed = coordinator.phase {
                        EmptyView()
                    } else if reviewPrepareError == nil {
                        reviewBottomActions
                    }
                } else if !isReviewing {
                    bottomActions
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .toolbar(.hidden, for: .navigationBar)
        .foregroundStyle(.white)
        .animation(.easeInOut(duration: 0.22), value: coordinator.phase.isWorking)
        .animation(.easeInOut(duration: 0.22), value: isReviewing)
        .task(id: selectedPhoto) {
            guard let selectedPhoto else { return }
            isTorchOn = false
            do {
                guard let data = try await selectedPhoto.loadTransferable(type: Data.self) else {
                    throw ImagePreprocessorError.unreadableImage
                }
                let place = PhotoLocationProvider.embeddedPlaceContext(in: data)
                presentReview(
                    data,
                    locationSource: .photoMetadata(place)
                )
                // Clear after presenting so the same pick cannot re-open when returning to this tab.
                // Do this last: clearing `selectedPhoto` cancels this task via `.task(id:)`.
                self.selectedPhoto = nil
            } catch is CancellationError {
                return
            } catch {
                coordinator.showFailure(error.localizedDescription)
                self.selectedPhoto = nil
            }
        }
        .task(id: pendingReview?.id) {
            await prepareReviewImage()
        }
        .task(id: pendingReview?.id) {
            await resolvePreviewPlace()
        }
        .sheet(isPresented: $helpSheetPresented) {
            ScanHelpSheet(
                demoAction: recognitionService.mode == .demo
                    ? {
                        presentReview(
                            SampleScanImage.jpegData(),
                            locationSource: captureLocationSource
                        )
                    }
                    : nil
            )
        }
        .onDisappear {
            isTorchOn = false
        }
    }

    private var cameraBackdrop: some View {
        LinearGradient(
            colors: [
                Color.black,
                CultureTheme.inkPrimary.opacity(0.94),
                CultureTheme.cinnabar.opacity(0.42),
            ],
            startPoint: .top,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .overlay {
            Image(systemName: "building.columns")
                .font(.system(size: 168, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.055))
        }
    }

    private var viewfinder: some View {
        RoundedRectangle(cornerRadius: 34, style: .continuous)
            .stroke(
                CultureTheme.antiqueGold.opacity(0.78),
                style: StrokeStyle(lineWidth: 1.5, dash: [12, 8])
            )
            .frame(maxWidth: 320, maxHeight: 390)
            .overlay(alignment: .top) {
                Text("将建筑、器物或纹样放入框内")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.38), in: Capsule())
                    .offset(y: 18)
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var bottomActions: some View {
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            GlassEffectContainer(spacing: 18) {
                cameraActionButtons
            }
        } else {
            cameraActionButtons
                .padding(12)
                .background(.ultraThinMaterial, in: Capsule())
        }
    }

    @ViewBuilder
    private var reviewBottomActions: some View {
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            GlassEffectContainer(spacing: 18) {
                reviewActionButtons
            }
        } else {
            reviewActionButtons
                .padding(12)
                .background(.ultraThinMaterial, in: Capsule())
        }
    }

    private var cameraActionButtons: some View {
        HStack(spacing: 18) {
            PhotosPicker(
                selection: $selectedPhoto,
                matching: .images,
                preferredItemEncoding: .current
            ) {
                Image(systemName: "photo.on.rectangle")
                    .frame(width: 48, height: 48)
            }
            .scanActionButtonStyle()
            .disabled(coordinator.phase.isWorking)
            .accessibilityLabel("从相册选择")

            Button {
                if isCameraAvailable {
                    captureRequestID = UUID()
                } else {
                    helpSheetPresented = true
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 74, height: 74)
                    Circle()
                        .stroke(CultureTheme.cinnabar, lineWidth: 4)
                        .frame(width: 62, height: 62)
                    Image(systemName: "camera.fill")
                        .foregroundStyle(CultureTheme.cinnabar)
                }
            }
            .buttonStyle(.plain)
            .disabled(coordinator.phase.isWorking)
            .accessibilityLabel("拍照并识别")
            .accessibilityIdentifier("scan.capture")

            Button {
                isTorchOn.toggle()
            } label: {
                Image(systemName: isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                    .foregroundStyle(isTorchOn ? CultureTheme.antiqueGold : .white)
                    .frame(width: 48, height: 48)
            }
            .scanActionButtonStyle()
            .disabled(!isCameraAvailable || coordinator.phase.isWorking)
            .accessibilityLabel(isTorchOn ? LocalizedStringKey("关闭手电筒") : "打开手电筒")
            .accessibilityIdentifier("scan.torch")
        }
    }

    private var reviewActionButtons: some View {
        HStack(spacing: 18) {
            Button {
                cancelReview()
            } label: {
                Text("取消")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 64, height: 48)
            }
            .scanActionButtonStyle()
            .disabled(preparedReview == nil)
            .accessibilityLabel("取消")
            .accessibilityIdentifier("focus.cancel")

            Button {
                confirmReview(useFocusRegion: true)
            } label: {
                ZStack {
                    Circle()
                        .fill(CultureTheme.cinnabar)
                        .frame(width: 74, height: 74)
                    Circle()
                        .stroke(.white.opacity(0.92), lineWidth: 3)
                        .frame(width: 62, height: 62)
                    Text("框选\n发送")
                        .font(.caption.weight(.bold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .disabled(preparedReview == nil)
            .accessibilityLabel("框选发送")
            .accessibilityIdentifier("focus.confirm")

            Button {
                confirmReview(useFocusRegion: false)
            } label: {
                Text("直接发送")
                    .font(.subheadline.weight(.semibold))
                    .frame(minWidth: 64, minHeight: 48)
            }
            .scanActionButtonStyle()
            .disabled(preparedReview == nil)
            .accessibilityLabel("直接发送")
            .accessibilityIdentifier("focus.sendFull")
        }
    }

    /// Working-phase status text lives in the view so it follows the in-app
    /// locale (`LocalizedStringKey`), not the device locale.
    private var progressMessage: LocalizedStringKey {
        switch coordinator.phase {
        case .idle: "准备扫描"
        case .preparing: "正在保护隐私并整理图片…"
        case .locating: "正在获取当前位置…"
        case .recognizing: "正在辨认文化线索…"
        case .failed(let message): LocalizedStringKey(message)
        }
    }

    private var progressCard: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(.white)
            Text(progressMessage)
                .font(.headline)
            if let locationNotice = coordinator.locationNotice {
                Text(locationNotice)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 22))
        .padding(.bottom, 16)
        .accessibilityElement(children: .combine)
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("这次没有认出来", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.78))
            HStack {
                Button("重新选择") {
                    selectedPhoto = nil
                    cancelReview()
                    coordinator.resetFailure()
                }
                .buttonStyle(.bordered)

                if let lastScanInput {
                    Button("重试") {
                        beginRecognition(
                            lastScanInput.imageData,
                            focusRegion: lastScanInput.focusRegion,
                            locationSource: lastScanInput.locationSource
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(CultureTheme.cinnabar)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 22))
        .padding(.bottom, 16)
    }

    private func reviewErrorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("无法准备图片", systemImage: "photo.badge.exclamationmark")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.78))
            Button("取消") {
                cancelReview()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 22))
        .padding(.bottom, 16)
    }

    private var captureLocationSource: ScanLocationSource {
        useLocation ? .currentDevice : .none
    }

    private var showsLocationPreview: Bool {
        guard isReviewing, !coordinator.phase.isWorking else { return false }
        if case .failed = coordinator.phase { return false }
        return pendingReview?.locationSource.showsPreview == true
    }

    private func presentReview(
        _ imageData: Data,
        locationSource: ScanLocationSource
    ) {
        preparedReview = nil
        reviewPrepareError = nil
        focusSelection = nil
        previewPlace = nil
        isResolvingPreviewPlace = false
        coordinator.resetFailure()
        pendingReview = PendingScanImage(
            data: imageData,
            locationSource: locationSource
        )
    }

    private func cancelReview() {
        pendingReview = nil
        preparedReview = nil
        reviewPrepareError = nil
        focusSelection = nil
        previewPlace = nil
        isResolvingPreviewPlace = false
    }

    private func resolvePreviewPlace() async {
        previewPlace = nil
        isResolvingPreviewPlace = false
        guard let pendingReview else { return }

        switch pendingReview.locationSource {
        case .photoMetadata(let place):
            previewPlace = place
        case .resolved(let place):
            previewPlace = place
        case .currentDevice:
            isResolvingPreviewPlace = true
            defer { isResolvingPreviewPlace = false }
            do {
                let place = try await locationProvider.requestBestPlace()
                try Task.checkCancellation()
                guard self.pendingReview?.id == pendingReview.id else { return }
                previewPlace = place
                self.pendingReview = PendingScanImage(
                    id: pendingReview.id,
                    data: pendingReview.data,
                    locationSource: .resolved(place)
                )
            } catch is CancellationError {
                return
            } catch {
                guard self.pendingReview?.id == pendingReview.id else { return }
                previewPlace = nil
            }
        case .none:
            previewPlace = nil
        }
    }

    private func confirmReview(useFocusRegion: Bool) {
        guard let pendingReview, let preparedReview else { return }
        beginRecognition(
            preparedReview.data,
            focusRegion: useFocusRegion
                ? focusSelection?.clamped()
                : nil,
            locationSource: pendingReview.locationSource
        )
    }

    private func prepareReviewImage() async {
        guard let pendingReview else {
            preparedReview = nil
            reviewPrepareError = nil
            return
        }

        preparedReview = nil
        reviewPrepareError = nil

        do {
            let sourceData = pendingReview.data
            let data = try await Task.detached(priority: .userInitiated) {
                try ImagePreprocessor.normalizedJPEG(from: sourceData)
            }.value
            try Task.checkCancellation()
            let pixelSize = try ImagePreprocessor.pixelSize(of: data)
            guard self.pendingReview?.id == pendingReview.id else { return }
            preparedReview = PreparedReviewImage(
                id: pendingReview.id,
                data: data,
                pixelSize: pixelSize
            )
            focusSelection = nil
        } catch is CancellationError {
            return
        } catch {
            guard self.pendingReview?.id == pendingReview.id else { return }
            reviewPrepareError = error.localizedDescription
        }
    }

    private func handleCapturedPhoto(_ data: Data?) {
        captureRequestID = nil
        isTorchOn = false
        guard let data else {
            coordinator.showFailure(String(localized: "无法读取拍摄的照片，请重试。"))
            return
        }
        presentReview(
            data,
            locationSource: captureLocationSource
        )
    }

    private func beginRecognition(
        _ normalizedImageData: Data,
        focusRegion: NormalizedImageRegion?,
        locationSource: ScanLocationSource
    ) {
        lastScanInput = LastScanInput(
            imageData: normalizedImageData,
            focusRegion: focusRegion,
            locationSource: locationSource
        )
        coordinator.begin(
            normalizedImageData: normalizedImageData,
            focusRegion: focusRegion,
            locationSource: locationSource,
            contextNote: "",
            userKnowledgeStates: knowledgeProgressStore.userKnowledgeStates(
                knowledgeStore: KnowledgeStore.shared
            ),
            service: recognitionService,
            onSuccess: { @MainActor @Sendable session in
                cancelReview()
                onRecognized(session)
            }
        )
    }
}

extension View {
    @ViewBuilder
    fileprivate func scanActionButtonStyle() -> some View {
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.plain)
        }
    }
}

private struct PendingScanImage: Identifiable {
    let id: UUID
    let data: Data
    let locationSource: ScanLocationSource

    init(
        id: UUID = UUID(),
        data: Data,
        locationSource: ScanLocationSource
    ) {
        self.id = id
        self.data = data
        self.locationSource = locationSource
    }
}

private extension ScanLocationSource {
    var showsPreview: Bool {
        switch self {
        case .currentDevice, .resolved, .photoMetadata:
            true
        case .none:
            false
        }
    }
}

private struct PreparedReviewImage {
    let id: UUID
    let data: Data
    let pixelSize: CGSize
}

private struct LastScanInput {
    let imageData: Data
    let focusRegion: NormalizedImageRegion?
    let locationSource: ScanLocationSource
}

private struct ScanHelpSheet: View {
    let demoAction: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("获得更可靠的结果", systemImage: "viewfinder")
            } description: {
                Text("保持画面清晰，尽量让对象占据取景框。拍摄纹样或铭文时靠近一些；无法使用相机时可从相册选择。")
            } actions: {
                if let demoAction {
                    Button("使用样例图片") {
                        dismiss()
                        Task { @MainActor in
                            demoAction()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(CultureTheme.cinnabar)
                    .accessibilityIdentifier("scan.useSampleImage")
                }
            }
            .cultureNavigationTitle("扫描帮助", showsBackButton: false)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    NavigationStack {
        ScanView { _ in }
    }
}
