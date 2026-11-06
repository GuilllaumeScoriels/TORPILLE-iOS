import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit
@preconcurrency import AVFoundation

enum CameraPickerMode: Equatable {
    case photoOnly
    case photoAndVideo
    case videoOnly

    var mediaTypes: [String] {
        switch self {
        case .photoOnly:
            return [UTType.image.identifier]
        case .photoAndVideo:
            return [UTType.image.identifier, UTType.movie.identifier]
        case .videoOnly:
            return [UTType.movie.identifier]
        }
    }
}

struct CameraMediaPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedFileURL: URL?
    let allowedTypes: CameraPickerMode

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        if allowedTypes == .videoOnly {
            return SwitchableVideoCameraViewController(
                onFinish: { url in
                    selectedFileURL = url
                    dismiss()
                },
                onCancel: {
                    dismiss()
                }
            )
        }

        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = allowedTypes.mediaTypes
        picker.videoQuality = .typeMedium
        picker.cameraCaptureMode = allowedTypes == .videoOnly ? .video : .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraMediaPicker

        init(_ parent: CameraMediaPicker) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let mediaURL = info[.mediaURL] as? URL {
                let ext = mediaURL.pathExtension.isEmpty ? "mov" : mediaURL.pathExtension.lowercased()
                let destination = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(ext)
                try? FileManager.default.removeItem(at: destination)
                do {
                    try FileManager.default.copyItem(at: mediaURL, to: destination)
                    parent.selectedFileURL = destination
                } catch {
                    parent.selectedFileURL = nil
                }
            } else if let image = info[.originalImage] as? UIImage {
                let destination = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("jpg")
                if let data = image.jpegData(compressionQuality: 0.85) {
                    try? data.write(to: destination, options: .atomic)
                    parent.selectedFileURL = destination
                }
            }
            parent.dismiss()
        }
    }
}

private final class SwitchableVideoCameraViewController: UIViewController, AVCaptureFileOutputRecordingDelegate {
    private enum CaptureState {
        case idle
        case starting
        case recording
        case finishing
    }

    private let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let sessionQueue = DispatchQueue(label: "com.torpille.switchable-video-camera")
    private var videoInput: AVCaptureDeviceInput?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var segments: [URL] = []
    private var shouldResumeAfterSwitch = false
    private var isFinishing = false
    private var captureState: CaptureState = .idle
    private var hasRequestedPermissions = false

    private let onFinish: (URL) -> Void
    private let onCancel: () -> Void

    private lazy var recordButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = .systemRed
        button.layer.cornerRadius = 34
        button.layer.borderWidth = 5
        button.layer.borderColor = UIColor.white.cgColor
        button.accessibilityLabel = "Démarrer l’enregistrement"
        button.addTarget(self, action: #selector(toggleRecording), for: .touchUpInside)
        return button
    }()

    private lazy var cancelButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Annuler", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        button.addTarget(self, action: #selector(cancelCapture), for: .touchUpInside)
        return button
    }()

    private lazy var flipButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "camera.rotate.fill"), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        button.layer.cornerRadius = 24
        button.addTarget(self, action: #selector(switchCamera), for: .touchUpInside)
        return button
    }()

    init(onFinish: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
        self.onFinish = onFinish
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        installControls()
        recordButton.isEnabled = false
        flipButton.isEnabled = false
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(switchCamera))
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Present permission errors only once the camera is on screen.
        guard !hasRequestedPermissions else { return }
        hasRequestedPermissions = true
        requestPermissionsAndConfigure()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func installControls() {
        view.addSubview(recordButton)
        view.addSubview(cancelButton)
        view.addSubview(flipButton)
        NSLayoutConstraint.activate([
            recordButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            recordButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            recordButton.widthAnchor.constraint(equalToConstant: 68),
            recordButton.heightAnchor.constraint(equalToConstant: 68),
            cancelButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            cancelButton.centerYAnchor.constraint(equalTo: recordButton.centerYAnchor),
            flipButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            flipButton.centerYAnchor.constraint(equalTo: recordButton.centerYAnchor),
            flipButton.widthAnchor.constraint(equalToConstant: 48),
            flipButton.heightAnchor.constraint(equalToConstant: 48)
        ])
    }

    private func requestPermissionsAndConfigure() {
        Task {
            let cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
            let microphoneGranted = await AVCaptureDevice.requestAccess(for: .audio)
            guard cameraGranted, microphoneGranted else {
                await MainActor.run {
                    self.showCameraError(
                        "Autorise la caméra et le microphone dans les Réglages pour filmer une torpille.",
                        offersSettings: true
                    )
                }
                return
            }
            sessionQueue.async { self.configureSession() }
        }
    }

    private func showCameraError(_ message: String, offersSettings: Bool = false) {
        let alert = UIAlertController(title: "Caméra indisponible", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Fermer", style: .cancel) { [weak self] _ in
            self?.cancelCapture()
        })
        if offersSettings {
            alert.addAction(UIAlertAction(title: "Ouvrir les Réglages", style: .default) { [weak self] _ in
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                self?.cancelCapture()
                UIApplication.shared.open(url)
            })
        }
        present(alert, animated: true)
    }

    private func configureSession() {
        guard !isFinishing else { return }
        session.beginConfiguration()
        session.sessionPreset = .high

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let cameraInput = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(cameraInput) else {
            session.commitConfiguration()
            DispatchQueue.main.async {
                self.showCameraError("Impossible de démarrer la caméra. Réessaie dans quelques instants.")
            }
            return
        }
        session.addInput(cameraInput)
        videoInput = cameraInput

        if let microphone = AVCaptureDevice.default(for: .audio),
           let microphoneInput = try? AVCaptureDeviceInput(device: microphone),
           session.canAddInput(microphoneInput) {
            session.addInput(microphoneInput)
        }
        guard session.canAddOutput(movieOutput) else {
            session.commitConfiguration()
            DispatchQueue.main.async {
                self.showCameraError("Impossible de préparer l’enregistrement vidéo. Réessaie dans quelques instants.")
            }
            return
        }
        session.addOutput(movieOutput)

        // AVFoundation raises an Objective-C exception if startRunning() is
        // called between beginConfiguration() and commitConfiguration().
        session.commitConfiguration()

        DispatchQueue.main.async {
            let layer = AVCaptureVideoPreviewLayer(session: self.session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = self.view.bounds
            self.view.layer.insertSublayer(layer, at: 0)
            self.previewLayer = layer
        }
        session.startRunning()
        let isRunning = session.isRunning
        DispatchQueue.main.async {
            self.recordButton.isEnabled = isRunning
            self.flipButton.isEnabled = isRunning
            if !isRunning {
                self.showCameraError("Impossible de démarrer la caméra. Réessaie dans quelques instants.")
            }
        }
    }

    @objc private func toggleRecording() {
        sessionQueue.async {
            switch self.captureState {
            case .idle:
                self.captureState = .starting
                self.startSegment()
                DispatchQueue.main.async { self.showRecordingButtonState() }
            case .starting:
                // startRecording(to:) becomes active asynchronously. Remember
                // the stop request and execute it from didStartRecordingTo.
                self.captureState = .finishing
                self.isFinishing = true
                DispatchQueue.main.async { self.showFinishingButtonState() }
            case .recording:
                self.captureState = .finishing
                self.isFinishing = true
                self.movieOutput.stopRecording()
                DispatchQueue.main.async { self.showFinishingButtonState() }
            case .finishing:
                break
            }
        }
    }

    private func showRecordingButtonState() {
        recordButton.backgroundColor = .white
        recordButton.layer.borderColor = UIColor.systemRed.cgColor
        recordButton.layer.cornerRadius = 12
        recordButton.accessibilityLabel = "Arrêter l’enregistrement"
    }

    private func showFinishingButtonState() {
        recordButton.isEnabled = false
        recordButton.alpha = 0.65
        recordButton.accessibilityLabel = "Finalisation de la vidéo"
    }

    private func startSegment() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        movieOutput.startRecording(to: url, recordingDelegate: self)
    }

    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        sessionQueue.async {
            if self.captureState == .finishing {
                self.movieOutput.stopRecording()
            } else {
                self.captureState = .recording
            }
        }
    }

    @objc private func switchCamera() {
        sessionQueue.async {
            guard !self.isFinishing else { return }
            if self.movieOutput.isRecording {
                self.shouldResumeAfterSwitch = true
                self.movieOutput.stopRecording()
            } else {
                self.replaceVideoInput()
            }
        }
    }

    private func replaceVideoInput() {
        guard let currentInput = videoInput else { return }
        let newPosition: AVCaptureDevice.Position = currentInput.device.position == .back ? .front : .back
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
              let newInput = try? AVCaptureDeviceInput(device: device) else { return }

        session.beginConfiguration()
        session.removeInput(currentInput)
        if session.canAddInput(newInput) {
            session.addInput(newInput)
            videoInput = newInput
        } else {
            session.addInput(currentInput)
        }
        session.commitConfiguration()
    }

    @objc private func cancelCapture() {
        sessionQueue.async {
            self.captureState = .finishing
            self.isFinishing = true
            if self.movieOutput.isRecording { self.movieOutput.stopRecording() }
            self.session.stopRunning()
            self.segments.forEach { try? FileManager.default.removeItem(at: $0) }
            DispatchQueue.main.async { self.onCancel() }
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        sessionQueue.async {
            let nsError = error as NSError?
            let finishedSuccessfully = error == nil
                || (nsError?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true)
            guard finishedSuccessfully,
                  FileManager.default.fileExists(atPath: outputFileURL.path) else {
                self.captureState = .idle
                if self.isFinishing { DispatchQueue.main.async { self.onCancel() } }
                return
            }
            self.segments.append(outputFileURL)

            if self.shouldResumeAfterSwitch {
                self.shouldResumeAfterSwitch = false
                self.replaceVideoInput()
                self.captureState = .starting
                self.startSegment()
                return
            }
            guard self.isFinishing else {
                self.captureState = .idle
                return
            }
            self.session.stopRunning()
            self.mergeSegmentsAndFinish()
        }
    }

    private func mergeSegmentsAndFinish() {
        guard !segments.isEmpty else {
            DispatchQueue.main.async { self.onCancel() }
            return
        }
        if segments.count == 1, let url = segments.first {
            DispatchQueue.main.async { self.onFinish(url) }
            return
        }

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            DispatchQueue.main.async { self.onCancel() }
            return
        }

        var cursor = CMTime.zero
        for url in segments {
            let asset = AVURLAsset(url: url)
            let range = CMTimeRange(start: .zero, duration: asset.duration)
            if let sourceVideo = asset.tracks(withMediaType: .video).first {
                try? videoTrack.insertTimeRange(range, of: sourceVideo, at: cursor)
                videoTrack.preferredTransform = sourceVideo.preferredTransform
            }
            if let sourceAudio = asset.tracks(withMediaType: .audio).first {
                try? audioTrack.insertTimeRange(range, of: sourceAudio, at: cursor)
            }
            cursor = CMTimeAdd(cursor, asset.duration)
        }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            DispatchQueue.main.async { self.onCancel() }
            return
        }
        exporter.outputURL = destination
        exporter.outputFileType = .mov
        exporter.exportAsynchronously {
            self.segments.forEach { try? FileManager.default.removeItem(at: $0) }
            DispatchQueue.main.async {
                if exporter.status == .completed {
                    self.onFinish(destination)
                } else {
                    self.onCancel()
                }
            }
        }
    }
}

struct VideoPicker: View {
    @Binding var selectedFileURL: URL?
    @EnvironmentObject private var languageService: AppLanguageService

    @State private var item: PhotosPickerItem?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PhotosPicker(selection: $item, matching: .videos) {
                Label(selectedFileURL == nil ? "Choisir une vidéo" : "Changer la vidéo", systemImage: "video.badge.plus")
            }
            .onChange(of: item) { _, newValue in
                guard let newValue else { return }
                Task { await loadFile(from: newValue) }
            }

            if let selectedFileURL {
                Text(selectedFileURL.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error {
                Text(languageService.localizedRuntimeMessage(error))
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @MainActor
    private func loadFile(from item: PhotosPickerItem) async {
        do {
            guard let temporaryURL = try await item.loadTransferable(type: TemporaryVideoFile.self)?.url else {
                throw TorpilleError.videoNotAvailable
            }
            let ext = temporaryURL.pathExtension.isEmpty ? "mov" : temporaryURL.pathExtension
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: temporaryURL, to: destination)
            selectedFileURL = destination
            error = nil
        } catch {
            self.error = userErrorMessage(error)
        }
    }
}

struct LibraryMediaPicker: View {
    @Binding var selectedItems: [PhotosPickerItem]
    @EnvironmentObject private var languageService: AppLanguageService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(languageService.phrase("Tu choisis ce que tu partages"), systemImage: "lock.shield")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal)
            Text(languageService.phrase("La galerie est affichée par iOS. Torpille accède uniquement aux photos et vidéos que tu sélectionnes. Rien n’est envoyé avant d’appuyer sur Envoyer. Les médias envoyés seront visibles par les membres de cette communauté."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            PhotosPicker(
                selection: $selectedItems,
                maxSelectionCount: 10,
                selectionBehavior: .continuousAndOrdered,
                matching: .any(of: [.images, .videos])
            ) {
                Label(languageService.phrase("Galerie"), systemImage: "photo.stack.fill")
            }
            .photosPickerStyle(.inline)
            .photosPickerDisabledCapabilities(.selectionActions)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text(selectedItems.isEmpty
                 ? languageService.phrase("Sélectionne jusqu’à 10 photos ou vidéos.")
                 : "\(selectedItems.count)/10 · \(languageService.phrase("média(s) sélectionné(s)"))")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
        .padding(.top, 12)
    }

}

enum LibraryMediaLoader {
    static func loadFiles(from items: [PhotosPickerItem]) async throws -> [URL] {
        var loadedURLs: [URL] = []
        do {
            for item in items {
                try Task.checkCancellation()
                let contentTypes = item.supportedContentTypes
                if contentTypes.contains(where: { $0.conforms(to: .movie) }) {
                    guard let url = try await item.loadTransferable(type: TemporaryVideoFile.self)?.url else {
                        throw TorpilleError.videoNotAvailable
                    }
                    loadedURLs.append(url)
                } else if contentTypes.contains(where: { $0.conforms(to: .image) }) {
                    guard let url = try await item.loadTransferable(type: TemporaryImageFile.self)?.url else {
                        throw TorpilleError.videoNotAvailable
                    }
                    loadedURLs.append(url)
                }
            }
            return loadedURLs
        } catch {
            loadedURLs.forEach { try? FileManager.default.removeItem(at: $0) }
            throw error
        }
    }
}

private struct TemporaryVideoFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { file in
            SentTransferredFile(file.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
            if FileManager.default.fileExists(atPath: copy.path) {
                try FileManager.default.removeItem(at: copy)
            }
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self(url: copy)
        }
    }
}

private struct TemporaryImageFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .image) { file in
            SentTransferredFile(file.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "jpg" : received.file.pathExtension
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self(url: copy)
        }
    }
}
