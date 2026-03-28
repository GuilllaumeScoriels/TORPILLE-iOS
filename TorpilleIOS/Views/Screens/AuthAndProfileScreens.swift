import SwiftUI

struct AuthScreen: View {
    @StateObject private var vm: AuthViewModel
    let onSignedIn: () -> Void
    let onSignedUp: () -> Void

    init(onSignedIn: @escaping () -> Void, onSignedUp: @escaping () -> Void, env: AppEnvironment) {
        self.onSignedIn = onSignedIn
        self.onSignedUp = onSignedUp
        _vm = StateObject(wrappedValue: AuthViewModel(authRepository: env.authRepository))
    }

    var body: some View {
        Form {
            Section("Connexion") {
                TextField("Email", text: $vm.email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                SecureField("Mot de passe", text: $vm.password)
                Button(vm.isLoading ? "Chargement…" : "Se connecter") {
                    vm.signIn(onSuccess: onSignedIn)
                }
                .disabled(vm.isLoading)
                Button("Créer un compte") {
                    vm.signUp(onSuccess: onSignedUp)
                }
                .disabled(vm.isLoading)
                Button("Mot de passe oublié") {
                    vm.resetPassword()
                }
                .disabled(vm.isLoading)
            }

            if let info = vm.infoMessage {
                Section { Text(info).foregroundStyle(.green) }
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
        _vm = StateObject(wrappedValue: ProfileViewModel(repo: env.userRepository, authRepository: env.authRepository))
    }

    var body: some View {
        Form {
            Section("Ton profil") {
                HStack {
                    Spacer()
                    EmojiAvatarView(profileIcon: vm.selectedProfileIcon, size: 96)
                    Spacer()
                }

                if !vm.email.isEmpty {
                    LabeledContent("Email") {
                        Text(vm.email)
                            .foregroundStyle(.secondary)
                    }
                }

                ProfileIconPicker(selectedIcon: $vm.selectedProfileIcon)

                TextField("Pseudo", text: $vm.pseudo)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

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
