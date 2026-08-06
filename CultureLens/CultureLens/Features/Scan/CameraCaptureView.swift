import SwiftUI

#if os(iOS)
  @preconcurrency import AVFoundation
  import UIKit

  struct CameraCaptureView: UIViewControllerRepresentable {
    let captureRequestID: UUID?
    let isTorchOn: Bool
    let onAvailabilityChanged: @MainActor @Sendable (Bool) -> Void
    let onTorchStateChanged: @MainActor @Sendable (Bool) -> Void
    let completion: @MainActor @Sendable (Data?) -> Void

    static var isCameraAvailable: Bool {
      AVCaptureDevice.default(
        .builtInWideAngleCamera,
        for: .video,
        position: .back
      ) != nil
    }

    @MainActor
    func makeCoordinator() -> Coordinator {
      Coordinator(
        onAvailabilityChanged: onAvailabilityChanged,
        onTorchStateChanged: onTorchStateChanged,
        completion: completion
      )
    }

    @MainActor
    func makeUIViewController(context: Context) -> LiveCameraViewController {
      LiveCameraViewController(coordinator: context.coordinator)
    }

    @MainActor
    func updateUIViewController(
      _ uiViewController: LiveCameraViewController,
      context: Context
    ) {
      context.coordinator.update(
        onAvailabilityChanged: onAvailabilityChanged,
        onTorchStateChanged: onTorchStateChanged,
        completion: completion
      )
      uiViewController.setTorch(isTorchOn)

      guard
        let captureRequestID,
        captureRequestID != context.coordinator.lastCaptureRequestID
      else {
        return
      }

      context.coordinator.lastCaptureRequestID = captureRequestID
      uiViewController.capturePhoto()
    }

    @MainActor
    static func dismantleUIViewController(
      _ uiViewController: LiveCameraViewController,
      coordinator: Coordinator
    ) {
      uiViewController.stop()
    }

    @MainActor
    final class Coordinator {
      fileprivate var lastCaptureRequestID: UUID?
      fileprivate var onAvailabilityChanged: @MainActor @Sendable (Bool) -> Void
      fileprivate var onTorchStateChanged: @MainActor @Sendable (Bool) -> Void
      fileprivate var completion: @MainActor @Sendable (Data?) -> Void

      init(
        onAvailabilityChanged: @escaping @MainActor @Sendable (Bool) -> Void,
        onTorchStateChanged: @escaping @MainActor @Sendable (Bool) -> Void,
        completion: @escaping @MainActor @Sendable (Data?) -> Void
      ) {
        self.onAvailabilityChanged = onAvailabilityChanged
        self.onTorchStateChanged = onTorchStateChanged
        self.completion = completion
      }

      fileprivate func update(
        onAvailabilityChanged: @escaping @MainActor @Sendable (Bool) -> Void,
        onTorchStateChanged: @escaping @MainActor @Sendable (Bool) -> Void,
        completion: @escaping @MainActor @Sendable (Data?) -> Void
      ) {
        self.onAvailabilityChanged = onAvailabilityChanged
        self.onTorchStateChanged = onTorchStateChanged
        self.completion = completion
      }
    }
  }

  @MainActor
  final class LiveCameraViewController: UIViewController {
    private let cameraSession: CameraSession
    private weak var coordinator: CameraCaptureView.Coordinator?
    private lazy var previewLayer = AVCaptureVideoPreviewLayer(
      session: cameraSession.session
    )
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?

    init(coordinator: CameraCaptureView.Coordinator) {
      cameraSession = CameraSession(
        onAvailabilityChanged: { [weak coordinator] isAvailable in
          guard let coordinator else { return }
          Task { @MainActor [coordinator] in
            coordinator.onAvailabilityChanged(isAvailable)
          }
        },
        onTorchStateChanged: { [weak coordinator] isOn in
          guard let coordinator else { return }
          Task { @MainActor [coordinator] in
            coordinator.onTorchStateChanged(isOn)
          }
        }
      )
      self.coordinator = coordinator
      super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
      super.viewDidLoad()
      view.backgroundColor = .clear
      previewLayer.videoGravity = .resizeAspectFill
      view.layer.addSublayer(previewLayer)
      if let device = AVCaptureDevice.default(
        .builtInWideAngleCamera,
        for: .video,
        position: .back
      ) {
        let rotationCoordinator = AVCaptureDevice.RotationCoordinator(
          device: device,
          previewLayer: previewLayer
        )
        self.rotationCoordinator = rotationCoordinator
        // Polling in `viewDidLayoutSubviews` alone misses the 180°
        // landscapeLeft ↔ landscapeRight flip, where the view's bounds
        // barely change and layout may not run. The coordinator's angle is
        // KVO-observable, so reapply it whenever it changes.
        rotationObservation = rotationCoordinator.observe(
          \.videoRotationAngleForHorizonLevelPreview,
          options: [.initial, .new]
        ) { [weak self] _, _ in
          Task { @MainActor [weak self] in
            self?.updatePreviewRotation()
          }
        }
      }
      updatePreviewRotation()
    }

    override func viewWillAppear(_ animated: Bool) {
      super.viewWillAppear(animated)
      cameraSession.prepareAndStart()
    }

    override func viewDidDisappear(_ animated: Bool) {
      super.viewDidDisappear(animated)
      cameraSession.stop()
    }

    override func viewDidLayoutSubviews() {
      super.viewDidLayoutSubviews()
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      previewLayer.frame = view.bounds
      CATransaction.commit()
      updatePreviewRotation()
    }

    /// Keeps the preview upright when the interface rotates (notably on
    /// iPad, where all orientations are supported). The preview layer's
    /// connection only exists once the session is running, so this reapplies
    /// the coordinator's angle both on layout and on KVO change.
    private func updatePreviewRotation() {
      guard
        let rotationCoordinator,
        let connection = previewLayer.connection
      else { return }
      let angle = rotationCoordinator.videoRotationAngleForHorizonLevelPreview
      if connection.isVideoRotationAngleSupported(angle) {
        connection.videoRotationAngle = angle
      }
    }

    func capturePhoto() {
      // Read on the main thread so the photo's EXIF orientation matches what
      // the user currently sees on screen.
      let rotationAngle =
        rotationCoordinator?.videoRotationAngleForHorizonLevelCapture ?? 90
      cameraSession.capturePhoto(rotationAngle: rotationAngle) { [weak coordinator] data in
        guard let coordinator else { return }
        Task { @MainActor [coordinator] in
          coordinator.completion(data)
        }
      }
    }

    func setTorch(_ enabled: Bool) {
      cameraSession.setTorch(enabled)
    }

    func stop() {
      cameraSession.stop()
    }
  }

  nonisolated private final class CameraSession: NSObject, AVCapturePhotoCaptureDelegate,
    @unchecked Sendable
  {
    let session = AVCaptureSession()

    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.culturelens.camera.session")
    private let onAvailabilityChanged: @Sendable (Bool) -> Void
    private let onTorchStateChanged: @Sendable (Bool) -> Void

    private var cameraDevice: AVCaptureDevice?
    private var isConfigured = false
    private var photoCompletion: (@Sendable (Data?) -> Void)?

    init(
      onAvailabilityChanged: @escaping @Sendable (Bool) -> Void,
      onTorchStateChanged: @escaping @Sendable (Bool) -> Void
    ) {
      self.onAvailabilityChanged = onAvailabilityChanged
      self.onTorchStateChanged = onTorchStateChanged
      super.init()
    }

    func prepareAndStart() {
      switch AVCaptureDevice.authorizationStatus(for: .video) {
      case .authorized:
        configureAndStart()

      case .notDetermined:
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
          guard let self else { return }
          if granted {
            self.configureAndStart()
          } else {
            self.onAvailabilityChanged(false)
          }
        }

      case .denied, .restricted:
        onAvailabilityChanged(false)

      @unknown default:
        onAvailabilityChanged(false)
      }
    }

    func capturePhoto(
      rotationAngle: CGFloat,
      completion: @escaping @Sendable (Data?) -> Void
    ) {
      sessionQueue.async { [weak self] in
        guard
          let self,
          self.isConfigured,
          self.session.isRunning,
          self.photoCompletion == nil
        else {
          completion(nil)
          return
        }

        self.photoCompletion = completion
        if
          let connection = self.photoOutput.connection(with: .video),
          connection.isVideoRotationAngleSupported(rotationAngle)
        {
          connection.videoRotationAngle = rotationAngle
        }
        let settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = self.photoOutput.maxPhotoQualityPrioritization
        self.photoOutput.capturePhoto(with: settings, delegate: self)
      }
    }

    func setTorch(_ enabled: Bool) {
      sessionQueue.async { [weak self] in
        self?.setTorchOnQueue(enabled)
      }
    }

    func stop() {
      sessionQueue.async { [weak self] in
        guard let self else { return }
        self.setTorchOnQueue(false)
        if self.session.isRunning {
          self.session.stopRunning()
        }
      }
    }

    private func configureAndStart() {
      sessionQueue.async { [weak self] in
        guard let self else { return }

        if !self.isConfigured {
          self.session.beginConfiguration()
          self.session.sessionPreset = .photo
          defer {
            self.session.commitConfiguration()
          }

          guard
            let device = AVCaptureDevice.default(
              .builtInWideAngleCamera,
              for: .video,
              position: .back
            ),
            let input = try? AVCaptureDeviceInput(device: device),
            self.session.canAddInput(input),
            self.session.canAddOutput(self.photoOutput)
          else {
            self.onAvailabilityChanged(false)
            return
          }

          self.session.addInput(input)
          self.session.addOutput(self.photoOutput)
          self.cameraDevice = device
          self.isConfigured = true
        }

        self.onAvailabilityChanged(true)
        if !self.session.isRunning {
          self.session.startRunning()
        }
      }
    }

    private func setTorchOnQueue(_ enabled: Bool) {
      guard
        let cameraDevice,
        cameraDevice.hasTorch,
        cameraDevice.isTorchAvailable,
        cameraDevice.isTorchModeSupported(enabled ? .on : .off)
      else {
        onTorchStateChanged(false)
        return
      }

      do {
        try cameraDevice.lockForConfiguration()
        defer {
          cameraDevice.unlockForConfiguration()
        }

        if enabled {
          try cameraDevice.setTorchModeOn(
            level: AVCaptureDevice.maxAvailableTorchLevel
          )
        } else {
          cameraDevice.torchMode = .off
        }
        onTorchStateChanged(cameraDevice.isTorchActive)
      } catch {
        onTorchStateChanged(false)
      }
    }

    func photoOutput(
      _ output: AVCapturePhotoOutput,
      didFinishProcessingPhoto photo: AVCapturePhoto,
      error: Error?
    ) {
      let data =
        error == nil
        ? photo.fileDataRepresentation()?.ownedCopy()
        : nil

      sessionQueue.async { [weak self] in
        guard let self else { return }
        let completion = self.photoCompletion
        self.photoCompletion = nil
        completion?(data)
      }
    }
  }

#else

  struct CameraCaptureView: View {
    let captureRequestID: UUID?
    let isTorchOn: Bool
    let onAvailabilityChanged: @MainActor @Sendable (Bool) -> Void
    let onTorchStateChanged: @MainActor @Sendable (Bool) -> Void
    let completion: @MainActor @Sendable (Data?) -> Void

    static let isCameraAvailable = false

    var body: some View {
      Color.clear
        .task {
          onAvailabilityChanged(false)
          onTorchStateChanged(false)
        }
    }
  }

#endif
