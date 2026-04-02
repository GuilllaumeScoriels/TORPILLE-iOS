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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                WelcomeHeroCard(
                    title: "Bienvenue sur Torpille",
                    subtitle: "Connecte-toi, crée ton compte et repars directement dans l'action avec une interface plus vivante.",
                    primarySymbol: "bolt.fill",
                    secondarySymbol: "sparkles",
                    cornerSymbol: "arrow.right.circle.fill",
                    accent: .ocean
                )

                VStack(alignment: .leading, spacing: 14) {
                    SectionTitleView(title: "Connexion", subtitle: "Entre tes identifiants pour rejoindre tes communautés.")

                    TextField("Email", text: $vm.email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    SecureField("Mot de passe", text: $vm.password)
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .padding(18)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

                Button {
                    vm.signIn(onSuccess: onSignedIn)
                } label: {
                    IllustratedActionButton(
                        title: vm.isLoading ? "Chargement…" : "Se connecter",
                        subtitle: "Récupère ton compte et retrouve tes parties en quelques secondes.",
                        systemImage: "person.crop.circle.badge.checkmark",
                        illustrationSymbol: "lock.shield.fill",
                        accent: .meadow
                    )
                }
                .buttonStyle(.plain)
                .disabled(vm.isLoading)

                Button {
                    vm.signUp(onSuccess: onSignedUp)
                } label: {
                    IllustratedActionButton(
                        title: "Créer un compte",
                        subtitle: "Prépare un nouveau profil pour commencer l'aventure.",
                        systemImage: "person.badge.plus.fill",
                        illustrationSymbol: "sparkles",
                        accent: .sunset
                    )
                }
                .buttonStyle(.plain)
                .disabled(vm.isLoading)

                Button {
                    vm.resetPassword()
                } label: {
                    IllustratedActionButton(
                        title: "Mot de passe oublié",
                        subtitle: "Reçois un email pour reprendre l'accès à ton compte.",
                        systemImage: "key.fill",
                        illustrationSymbol: "envelope.open.fill",
                        accent: .gold
                    )
                }
                .buttonStyle(.plain)
                .disabled(vm.isLoading)

                if let info = vm.infoMessage {
                    Text(info)
                        .foregroundStyle(.green)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                if let error = vm.error {
                    Text(error)
                        .foregroundStyle(.red)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .padding()
        }
        .background(Color(.systemBackground))
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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                WelcomeHeroCard(
                    title: "Crée ton profil",
                    subtitle: "Ajoute une photo, choisis un pseudo et rends ton arrivée plus fun dès le premier écran.",
                    primarySymbol: "person.crop.circle.fill",
                    secondarySymbol: "camera.aperture",
                    cornerSymbol: "pencil.circle.fill",
                    accent: .violet
                )

                VStack(spacing: 16) {
                    HStack {
                        Spacer()
                        ProfileAvatarImageView(
                            imageData: vm.selectedPhotoData,
                            photoURL: nil,
                            fallbackSymbol: "person.crop.circle.fill",
                            size: 96
                        )
                        Spacer()
                    }

                    if !vm.email.isEmpty {
                        HStack(spacing: 12) {
                            Image(systemName: "envelope.fill")
                                .foregroundStyle(ActionAccent.ocean.tint)
                                .frame(width: 36, height: 36)
                                .background(ActionAccent.ocean.tint.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Email")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(vm.email)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                    ProfilePhotoPicker(selectedImageData: $vm.selectedPhotoData)

                    TextField("Pseudo", text: $vm.pseudo)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .padding(18)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

                Button {
                    vm.save(onDone: onDone)
                } label: {
                    IllustratedActionButton(
                        title: vm.isSaving ? "Enregistrement…" : "Continuer",
                        subtitle: "Valide ton profil pour entrer dans l'application.",
                        systemImage: "arrow.right.circle.fill",
                        illustrationSymbol: "checkmark.seal.fill",
                        accent: .meadow
                    )
                }
                .buttonStyle(.plain)
                .disabled(vm.isSaving || vm.pseudo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let error = vm.error {
                    Text(error)
                        .foregroundStyle(.red)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .padding()
        }
        .background(Color(.systemBackground))
        .navigationTitle("Profil")
    }
}
