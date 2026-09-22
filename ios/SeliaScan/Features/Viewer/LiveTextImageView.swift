import SwiftUI
import VisionKit
import UIKit

@available(iOS 16.0, *)
struct LiveTextImageView: UIViewRepresentable {
    let image: UIImage
    let allowsZoom: Bool

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = allowsZoom ? 5 : 1
        scrollView.isScrollEnabled = allowsZoom
        scrollView.delegate = context.coordinator

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.frame = scrollView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.addSubview(imageView)

        let interaction = ImageAnalysisInteraction()
        imageView.addInteraction(interaction)
        context.coordinator.imageView = imageView
        context.coordinator.interaction = interaction
        context.coordinator.update(with: image)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        scrollView.maximumZoomScale = allowsZoom ? 5 : 1
        scrollView.isScrollEnabled = allowsZoom
        if !allowsZoom, scrollView.zoomScale != 1 { scrollView.setZoomScale(1, animated: false) }
        context.coordinator.update(with: image)
    }

    static func dismantleUIView(_ uiView: UIScrollView, coordinator: Coordinator) {
        coordinator.cancelAnalysis()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate {
        var interaction: ImageAnalysisInteraction?
        var imageView: UIImageView?
        private var displayedImage: UIImage?
        private var analysisTask: Task<Void, Never>?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func update(with image: UIImage) {
            guard displayedImage !== image else { return }
            displayedImage = image
            imageView?.image = image
            interaction?.analysis = nil
            analysisTask?.cancel()

            analysisTask = Task { [weak self] in
                let configuration = ImageAnalyzer.Configuration([.text])
                guard let analysis = try? await ImageAnalyzer().analyze(image, configuration: configuration),
                      !Task.isCancelled,
                      self?.displayedImage === image else { return }
                self?.interaction?.analysis = analysis
                self?.interaction?.preferredInteractionTypes = [.textSelection, .dataDetectors]
            }
        }

        func cancelAnalysis() {
            analysisTask?.cancel()
            analysisTask = nil
        }
    }
}
