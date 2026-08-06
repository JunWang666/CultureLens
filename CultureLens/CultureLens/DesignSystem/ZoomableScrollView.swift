import SwiftUI
import UIKit

/// UIScrollView-backed zoom/pan canvas. Pinch zoom is handled entirely by the
/// system (`viewForZooming(in:)`), so zooming stays anchored at the finger
/// centroid with native inertia and rubber-banding — unlike `scaleEffect`,
/// which always scales around one fixed anchor.
struct ZoomableScrollView<Content: View>: UIViewRepresentable {
  /// Unscaled content size (point size at 100% zoom).
  let contentSize: CGSize
  /// Live zoom scale, two-way: toolbar buttons write it, pinch updates it.
  @Binding var zoomScale: CGFloat
  /// Fit-to-viewport scale, computed here because the viewport lives in UIKit.
  @Binding var fittedZoomScale: CGFloat
  /// Bump to re-center on `centerPoint` (content coordinates).
  @Binding var centerRequest: Int
  /// Content-coordinate point that `centerRequest` scrolls into view.
  let centerPoint: CGPoint
  /// Start fitted to the viewport instead of at the bound `zoomScale`.
  var fitOnAppear: Bool = false

  /// The hosted content is rendered by a manually created UIHostingController,
  /// which does not inherit the surrounding SwiftUI environment — forward the
  /// pieces the graph canvas actually reads (`LocalizedPackText`).
  @Environment(AppLanguageStore.self) private var languageStore: AppLanguageStore?
  @Environment(\.locale) private var locale

  @ViewBuilder var content: Content

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  func makeUIView(context: Context) -> ZoomCanvasScrollView {
    let scrollView = ZoomCanvasScrollView()
    scrollView.delegate = context.coordinator
    scrollView.minimumZoomScale = GraphZoom.minimumScale
    scrollView.maximumZoomScale = GraphZoom.maximumScale
    scrollView.bouncesZoom = true
    scrollView.contentInsetAdjustmentBehavior = .never
    scrollView.onLayout = { [weak coordinator = context.coordinator] scrollView in
      coordinator?.handleLayout(scrollView)
    }

    let hostedView = context.coordinator.hostingController.view!
    hostedView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.addSubview(hostedView)
    let widthConstraint = hostedView.widthAnchor.constraint(equalToConstant: contentSize.width)
    let heightConstraint = hostedView.heightAnchor.constraint(equalToConstant: contentSize.height)
    NSLayoutConstraint.activate([
      hostedView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
      hostedView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
      hostedView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
      hostedView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
      widthConstraint,
      heightConstraint,
    ])
    context.coordinator.widthConstraint = widthConstraint
    context.coordinator.heightConstraint = heightConstraint
    return scrollView
  }

  func updateUIView(_ scrollView: ZoomCanvasScrollView, context: Context) {
    let coordinator = context.coordinator
    coordinator.parent = self
    coordinator.hostingController.rootView = AnyView(
      content
        .environment(languageStore)
        .environment(\.locale, locale)
    )
    coordinator.attachToViewControllerHierarchyIfNeeded(from: scrollView)
    coordinator.updateContentSize(contentSize)

    let centerChanged = coordinator.lastCenterRequest != centerRequest

    // Never fight an in-flight gesture or programmatic zoom animation; leave
    // `lastCenterRequest` untouched so the pending center re-fires later.
    guard !scrollView.isZooming, !coordinator.isApplyingProgrammaticZoom else { return }
    coordinator.lastCenterRequest = centerRequest

    let target = GraphZoom.clamped(zoomScale)
    if abs(scrollView.zoomScale - target) > 0.0005 {
      coordinator.applyProgrammaticZoom(
        target,
        in: scrollView,
        animated: true,
        thenCenter: centerChanged ? (centerPoint, true) : nil
      )
    } else if centerChanged, coordinator.didInitializeZoom {
      coordinator.centerOn(centerPoint, in: scrollView, animated: true)
    }
  }

  @MainActor
  final class Coordinator: NSObject, UIScrollViewDelegate {
    var parent: ZoomableScrollView
    let hostingController: UIHostingController<AnyView>
    var widthConstraint: NSLayoutConstraint!
    var heightConstraint: NSLayoutConstraint!
    var lastCenterRequest: Int
    var didInitializeZoom = false
    private(set) var isApplyingProgrammaticZoom = false
    private var pendingCenter: (point: CGPoint, animated: Bool)?

    init(_ parent: ZoomableScrollView) {
      self.parent = parent
      self.lastCenterRequest = parent.centerRequest
      self.hostingController = UIHostingController(rootView: AnyView(parent.content))
      super.init()
      hostingController.view.backgroundColor = .clear
      hostingController.sizingOptions = []
    }

    // MARK: UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
      hostingController.view
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
      centerContentIfNeeded(in: scrollView)
      guard !isApplyingProgrammaticZoom else { return }
      if abs(parent.zoomScale - scrollView.zoomScale) > 0.0005 {
        parent.zoomScale = scrollView.zoomScale
      }
    }

    func scrollViewDidEndZooming(
      _ scrollView: UIScrollView,
      with view: UIView?,
      atScale scale: CGFloat
    ) {
      finishProgrammaticZoom(in: scrollView)
    }

    // MARK: Layout

    /// Runs from `layoutSubviews`: the viewport size is only knowable once
    /// UIKit lays out, which is also when the initial zoom can be applied.
    func handleLayout(_ scrollView: ZoomCanvasScrollView) {
      let viewport = scrollView.bounds.size
      guard viewport.width > 0, viewport.height > 0 else { return }

      // Half-viewport margins on every side, so edge nodes can be dragged to
      // the middle of the screen instead of sticking to the viewport edge.
      let inset = UIEdgeInsets(
        top: viewport.height / 2,
        left: viewport.width / 2,
        bottom: viewport.height / 2,
        right: viewport.width / 2
      )
      if scrollView.contentInset != inset {
        scrollView.contentInset = inset
      }

      let fitted = GraphZoom.fittedScale(
        contentSize: parent.contentSize,
        viewportSize: viewport
      )
      if abs(parent.fittedZoomScale - fitted) > 0.0005 {
        DispatchQueue.main.async { self.parent.fittedZoomScale = fitted }
      }

      guard !didInitializeZoom else { return }
      didInitializeZoom = true
      let initial = parent.fitOnAppear ? fitted : GraphZoom.clamped(parent.zoomScale)
      applyProgrammaticZoom(
        initial,
        in: scrollView,
        animated: false,
        thenCenter: (parent.centerPoint, false)
      )
    }

    func updateContentSize(_ contentSize: CGSize) {
      guard widthConstraint.constant != contentSize.width
        || heightConstraint.constant != contentSize.height
      else { return }
      widthConstraint.constant = contentSize.width
      heightConstraint.constant = contentSize.height
    }

    // MARK: Zoom / center

    func applyProgrammaticZoom(
      _ scale: CGFloat,
      in scrollView: UIScrollView,
      animated: Bool,
      thenCenter: (point: CGPoint, animated: Bool)?
    ) {
      isApplyingProgrammaticZoom = true
      pendingCenter = thenCenter
      scrollView.setZoomScale(scale, animated: animated)
      if !animated {
        // Without animation scrollViewDidEndZooming is not guaranteed.
        finishProgrammaticZoom(in: scrollView)
      }
    }

    func centerOn(_ point: CGPoint, in scrollView: UIScrollView, animated: Bool) {
      let offset = CGPoint(
        x: point.x * scrollView.zoomScale - scrollView.bounds.width / 2,
        y: point.y * scrollView.zoomScale - scrollView.bounds.height / 2
      )
      scrollView.setContentOffset(offset, animated: animated)
    }

    private func finishProgrammaticZoom(in scrollView: UIScrollView) {
      isApplyingProgrammaticZoom = false
      if abs(parent.zoomScale - scrollView.zoomScale) > 0.0005 {
        parent.zoomScale = scrollView.zoomScale
      }
      if let pendingCenter {
        self.pendingCenter = nil
        centerOn(pendingCenter.point, in: scrollView, animated: pendingCenter.animated)
      }
    }

    /// Keeps the canvas visually centered while it is smaller than the viewport.
    private func centerContentIfNeeded(in scrollView: UIScrollView) {
      guard let hostedView = hostingController.view else { return }
      let offsetX = max((scrollView.bounds.width - scrollView.contentSize.width) / 2, 0)
      let offsetY = max((scrollView.bounds.height - scrollView.contentSize.height) / 2, 0)
      hostedView.center = CGPoint(
        x: scrollView.contentSize.width / 2 + offsetX,
        y: scrollView.contentSize.height / 2 + offsetY
      )
    }

    /// Popovers and context menus inside the hosted SwiftUI content only
    /// present when the hosting controller is in the view-controller chain.
    func attachToViewControllerHierarchyIfNeeded(from view: UIView) {
      guard hostingController.parent == nil else { return }
      var responder: UIResponder? = view.next
      while let current = responder, !(current is UIViewController) {
        responder = current.next
      }
      guard let viewController = responder as? UIViewController else { return }
      viewController.addChild(hostingController)
      hostingController.didMove(toParent: viewController)
    }
  }
}

/// Reports UIKit layout passes so the coordinator can compute the fitted zoom
/// and apply the initial zoom once the viewport has a real size.
final class ZoomCanvasScrollView: UIScrollView {
  var onLayout: ((ZoomCanvasScrollView) -> Void)?

  override func layoutSubviews() {
    super.layoutSubviews()
    onLayout?(self)
  }
}
