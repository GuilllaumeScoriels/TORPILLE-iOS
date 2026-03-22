/**
 Fichier : VideoPicker.swift
 Rôle :
 - Permet à l'utilisateur de choisir une vidéo depuis la photothèque iOS.

 Ce que fait ce fichier :
 - Utilise `PhotosPicker` pour sélectionner un film.
 - Copie le fichier dans un emplacement temporaire stable afin de pouvoir
   l'envoyer ensuite vers Firebase Storage.

 Pourquoi c'est utile :
 - Le portage iOS fournit un flux concret d'envoi vidéo sans dépendre d'UIKit lourd.
 */

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

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
                Task {
                    await loadFile(from: newValue)
                }
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
