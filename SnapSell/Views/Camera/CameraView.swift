import SwiftUI
import UIKit
import AVFoundation
import Combine

// Thin SwiftUI bridge — all layout is handled by UIKit below.
struct CameraView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void

    func makeUIViewController(context: Context) -> CameraViewController {
        CameraViewController(onCapture: onCapture)
    }
    func updateUIViewController(_ vc: CameraViewController, context: Context) {}
}

// MARK: - CameraViewController

final class CameraViewController: UIViewController {

    // MARK: Dependencies
    private let onCapture: (UIImage) -> Void
    private let camera = CameraManager()
    private var cancellables = Set<AnyCancellable>()

    // MARK: Preview
    private var previewLayer: AVCaptureVideoPreviewLayer!

    // MARK: UI elements
    private let loadingIndicator  = UIActivityIndicatorView(style: .medium)
    private let titleLabel        = UILabel()
    private let flashButton       = UIButton(type: .system)
    private let viewfinderView    = ViewfinderView()
    private let hintLabel         = UILabel()
    private let libraryButton     = UIButton(type: .system)
    private let shutterButton     = UIButton(type: .custom)
    private let flipButton        = UIButton(type: .system)

    // MARK: Init
    init(onCapture: @escaping (UIImage) -> Void) {
        self.onCapture = onCapture
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupPreview()
        setupSubviews()
        setupConstraints()
        observeCamera()
        Task { await camera.checkPermissionsAndSetup() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        camera.stopSession()
    }

    // MARK: - Preview Setup

    private func setupPreview() {
        previewLayer = AVCaptureVideoPreviewLayer(session: camera.session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.insertSublayer(previewLayer, at: 0)
    }

    // MARK: - Subviews

    private func setupSubviews() {
        // Loading spinner (shown until session starts)
        loadingIndicator.color = .white
        loadingIndicator.startAnimating()

        // Title
        let attributed = NSAttributedString(
            string: "SNAPSELL",
            attributes: [
                .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.4),
                .kern: 2.0
            ]
        )
        titleLabel.attributedText = attributed

        // Flash button
        flashButton.setImage(UIImage(systemName: "bolt.badge.a"), for: .normal)
        flashButton.tintColor = .white
        flashButton.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        flashButton.layer.cornerRadius = 19
        flashButton.clipsToBounds = true
        flashButton.addTarget(self, action: #selector(didTapFlash), for: .touchUpInside)

        // Viewfinder
        viewfinderView.backgroundColor = .clear

        // Hint
        hintLabel.text = "Point at any item to identify & price"
        hintLabel.font = .systemFont(ofSize: 13, weight: .medium)
        hintLabel.textColor = UIColor.white.withAlphaComponent(0.5)
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 0

        // Library button
        configureIconButton(libraryButton, icon: "photo.on.rectangle")

        // Shutter button — outer white circle
        shutterButton.backgroundColor = .white
        shutterButton.layer.cornerRadius = 36
        shutterButton.clipsToBounds = true
        shutterButton.addTarget(self, action: #selector(didTapShutter), for: .touchUpInside)

        // Shutter inner grey circle
        let inner = UIView()
        inner.backgroundColor = UIColor.systemGray5
        inner.layer.cornerRadius = 29
        inner.isUserInteractionEnabled = false
        inner.translatesAutoresizingMaskIntoConstraints = false
        shutterButton.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.centerXAnchor.constraint(equalTo: shutterButton.centerXAnchor),
            inner.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor),
            inner.widthAnchor.constraint(equalToConstant: 58),
            inner.heightAnchor.constraint(equalToConstant: 58),
        ])

        // Flip button
        configureIconButton(flipButton, icon: "arrow.triangle.2.circlepath.camera")
        flipButton.addTarget(self, action: #selector(didTapFlip), for: .touchUpInside)

        // Add everything to view
        [loadingIndicator, titleLabel, flashButton,
         viewfinderView, hintLabel,
         libraryButton, shutterButton, flipButton
        ].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
    }

    private func configureIconButton(_ button: UIButton, icon: String) {
        let cfg = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        button.setImage(UIImage(systemName: icon, withConfiguration: cfg), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        button.layer.cornerRadius = 25
        button.clipsToBounds = true
    }

    // MARK: - Constraints

    private func setupConstraints() {
        // 49 pt = height of the custom tab bar drawn in ContentView
        let tabBarH: CGFloat = 49

        NSLayoutConstraint.activate([

            // ── Loading indicator ────────────────────────────────────────
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            // ── Top bar ──────────────────────────────────────────────────
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),

            flashButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            flashButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            flashButton.widthAnchor.constraint(equalToConstant: 38),
            flashButton.heightAnchor.constraint(equalToConstant: 38),

            // ── Viewfinder ───────────────────────────────────────────────
            viewfinderView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            viewfinderView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            viewfinderView.widthAnchor.constraint(equalToConstant: 240),
            viewfinderView.heightAnchor.constraint(equalToConstant: 288),

            // ── Hint label ───────────────────────────────────────────────
            hintLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hintLabel.topAnchor.constraint(equalTo: viewfinderView.bottomAnchor, constant: 12),
            hintLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            hintLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),

            // ── Bottom bar ───────────────────────────────────────────────
            // safeAreaLayoutGuide.bottom already accounts for the home indicator.
            // Subtract an additional tabBarH to clear the custom tab bar.
            shutterButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutterButton.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -(tabBarH + 8)),
            shutterButton.widthAnchor.constraint(equalToConstant: 72),
            shutterButton.heightAnchor.constraint(equalToConstant: 72),

            libraryButton.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor),
            libraryButton.trailingAnchor.constraint(
                equalTo: shutterButton.leadingAnchor, constant: -48),
            libraryButton.widthAnchor.constraint(equalToConstant: 50),
            libraryButton.heightAnchor.constraint(equalToConstant: 50),

            flipButton.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor),
            flipButton.leadingAnchor.constraint(
                equalTo: shutterButton.trailingAnchor, constant: 48),
            flipButton.widthAnchor.constraint(equalToConstant: 50),
            flipButton.heightAnchor.constraint(equalToConstant: 50),
        ])
    }

    // MARK: - Observe camera state

    private func observeCamera() {
        camera.$isSessionRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] running in
                self?.loadingIndicator.isHidden = running
            }
            .store(in: &cancellables)

        camera.$flashMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                self?.updateFlashIcon(mode)
            }
            .store(in: &cancellables)
    }

    private func updateFlashIcon(_ mode: AVCaptureDevice.FlashMode) {
        let name: String
        switch mode {
        case .auto: name = "bolt.badge.a"
        case .on:   name = "bolt.fill"
        case .off:  name = "bolt.slash"
        @unknown default: name = "bolt.badge.a"
        }
        flashButton.setImage(UIImage(systemName: name), for: .normal)
    }

    // MARK: - Actions

    @objc private func didTapFlash() {
        camera.cycleFlash()
    }

    @objc private func didTapShutter() {
        // Shutter scale animation
        UIView.animate(withDuration: 0.1, animations: {
            self.shutterButton.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
        }) { _ in
            UIView.animate(withDuration: 0.15) {
                self.shutterButton.transform = .identity
            }
        }

        // Flash overlay
        let flash = UIView(frame: view.bounds)
        flash.backgroundColor = .white
        flash.alpha = 0
        view.addSubview(flash)
        UIView.animate(withDuration: 0.05) { flash.alpha = 1 } completion: { _ in
            UIView.animate(withDuration: 0.2) { flash.alpha = 0 } completion: { _ in
                flash.removeFromSuperview()
            }
        }

        Task {
            guard let image = try? await camera.capturePhoto() else { return }
            await MainActor.run { onCapture(image) }
        }
    }

    @objc private func didTapFlip() {
        camera.flipCamera()
    }
}

// MARK: - ViewfinderView

final class ViewfinderView: UIView {
    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let color = UIColor(named: "AccentYellow") ?? .yellow
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(2.5)
        ctx.setLineCap(.round)

        let len: CGFloat = 22
        let r: CGFloat   = 8

        // Explicit path per corner
        let W = rect.width, H = rect.height

        // Top-left
        ctx.move(to: CGPoint(x: 0,     y: len))
        ctx.addLine(to: CGPoint(x: 0,  y: r))
        ctx.addArc(center: CGPoint(x: r, y: r), radius: r,
                   startAngle: .pi, endAngle: .pi * 1.5, clockwise: false)
        ctx.addLine(to: CGPoint(x: len, y: 0))

        // Top-right
        ctx.move(to: CGPoint(x: W - len, y: 0))
        ctx.addLine(to: CGPoint(x: W - r, y: 0))
        ctx.addArc(center: CGPoint(x: W - r, y: r), radius: r,
                   startAngle: .pi * 1.5, endAngle: 0, clockwise: false)
        ctx.addLine(to: CGPoint(x: W, y: len))

        // Bottom-left
        ctx.move(to: CGPoint(x: 0, y: H - len))
        ctx.addLine(to: CGPoint(x: 0, y: H - r))
        ctx.addArc(center: CGPoint(x: r, y: H - r), radius: r,
                   startAngle: .pi, endAngle: .pi * 0.5, clockwise: true)
        ctx.addLine(to: CGPoint(x: len, y: H))

        // Bottom-right
        ctx.move(to: CGPoint(x: W - len, y: H))
        ctx.addLine(to: CGPoint(x: W - r, y: H))
        ctx.addArc(center: CGPoint(x: W - r, y: H - r), radius: r,
                   startAngle: .pi * 0.5, endAngle: 0, clockwise: true)
        ctx.addLine(to: CGPoint(x: W, y: H - len))

        ctx.strokePath()
    }
}
