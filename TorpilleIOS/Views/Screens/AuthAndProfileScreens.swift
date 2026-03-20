/**
 Fichier : AuthAndProfileScreens.swift
 Rôle :
 - Regroupe les écrans d'authentification et de configuration du profil.

 Ce que fait ce fichier :
 - Permet de créer un compte, se connecter et enregistrer un pseudo.
 - Réutilise les view models dédiés pour rester proche de l'architecture Android.
 */

import SwiftUI

struct AuthScreen: View {
    @StateObject private var vm: AuthViewModel
    let onAuthed: () -> Void

    init(onAuthed: @escaping () -> Void, env: AppEnvironment) {
        self.onAuthed = onAuthed
        _vm = StateObject(wrappedValue: AuthViewModel(authRepository: env.authRepository))
    }

    var body: some View {
        Form {
            Section("Connexion") {
                TextField("Email", text: $vm.email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                SecureField("Mot de passe", text: $vm.password)
                Button(vm.isLoading ? "Chargement…" : "Se connecter") {
                    vm.signIn(onSuccess: onAuthed)
                }
                .disabled(vm.isLoading)
                Button("Créer un compte") {
                    vm.signUp(onSuccess: onAuthed)
                }
                .disabled(vm.isLoading)
            }

            if let error = vm.error {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Torpille")
    }
}

struct ProfileSetupScreen: View {
    @StateObject private var vm: ProfileViewModel
    let onDone: () -> Void

    init(onDone: @escaping () -> Void, env: AppEnvironment) {
        self.onDone = onDone
        _vm = StateObject(wrappedValue: ProfileViewModel(repo: env.userRepository))
    }

    var body: some View {
        Form {
            Section("Ton profil") {
                TextField("Pseudo", text: $vm.pseudo)
                Button(vm.isSaving ? "Enregistrement…" : "Continuer") {
                    vm.save(onDone: onDone)
                }
                .disabled(vm.isSaving || vm.pseudo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let error = vm.error {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Profil")
    }
}
