import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

enum CameraPickerMode: Equatable {
    case photoAndVideo
    case videoOnly

    var mediaTypes: [String] {
        switch self {
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

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = allowedTypes.mediaTypes
        picker.videoQuality = .typeMedium
        picker.cameraCaptureMode = allowedTypes == .videoOnly ? .video : .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

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

struct VideoPicker: View {
    @Binding var selectedFileURL: URL?

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
                Text(error)
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
            self.error = error.localizedDescription
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
