import SwiftUI

struct AuthScreen: View {
    @StateObject private var vm: AuthViewModel
    @ObservedObject private var languageService: AppLanguageService
    let onSignedIn: () -> Void
    let onSignedUp: () -> Void

    init(onSignedIn: @escaping () -> Void, onSignedUp: @escaping () -> Void, env: AppEnvironment) {
        self.onSignedIn = onSignedIn
        self.onSignedUp = onSignedUp
        _languageService = ObservedObject(wrappedValue: env.languageService)
        _vm = StateObject(wrappedValue: AuthViewModel(authRepository: env.authRepository, languageService: env.languageService))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                WelcomeHeroCard(
                    title: languageService.text(.authWelcomeTitle),
                    subtitle: languageService.text(.authWelcomeSubtitle),
                    primarySymbol: "bolt.fill",
                    secondarySymbol: "sparkles",
                    cornerSymbol: "arrow.right.circle.fill",
                    accent: .ocean
                )

                VStack(alignment: .leading, spacing: 14) {
                    Picker(languageService.text(.appLanguage), selection: $languageService.language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.nativeLabel).tag(language)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    SectionTitleView(title: languageService.text(.authSectionTitle), subtitle: languageService.text(.authSectionSubtitle))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(languageService.text(.authVerificationNoticeTitle))
                            .font(.subheadline.weight(.semibold))
                        Text(languageService.text(.authVerificationNoticeSubtitle))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    TextField(languageService.text(.authEmailPlaceholder), text: $vm.email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    SecureField(languageService.text(.authPasswordPlaceholder), text: $vm.password)
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
                        title: vm.isLoading ? languageService.text(.authLoading) : languageService.text(.authSignIn),
                        subtitle: languageService.text(.authSignInSubtitle),
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
                        title: languageService.text(.authSignUp),
                        subtitle: languageService.text(.authSignUpSubtitle),
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
                        title: languageService.text(.authForgotPassword),
                        subtitle: languageService.text(.authForgotPasswordSubtitle),
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
    @ObservedObject private var languageService: AppLanguageService
    let onDone: () -> Void

    init(onDone: @escaping () -> Void, env: AppEnvironment) {
        self.onDone = onDone
        _languageService = ObservedObject(wrappedValue: env.languageService)
        _vm = StateObject(wrappedValue: ProfileViewModel(repo: env.userRepository, authRepository: env.authRepository))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                WelcomeHeroCard(
                    title: languageService.text(.profileSetupTitle),
                    subtitle: languageService.text(.profileSetupSubtitle),
                    primarySymbol: "person.crop.circle.fill",
                    secondarySymbol: "camera.aperture",
                    cornerSymbol: "pencil.circle.fill",
                    accent: .violet
                )

                VStack(spacing: 16) {
                    HStack {
                        Spacer()
                        if vm.selectedPhotoData == nil, !vm.selectedProfileIcon.isEmpty {
                            EmojiAvatarView(profileIcon: vm.selectedProfileIcon, size: 96)
                        } else {
                            ProfileAvatarImageView(
                                imageData: vm.selectedPhotoData,
                                photoURL: nil,
                                fallbackSymbol: "person.crop.circle.fill",
                                size: 96
                            )
                        }
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
                                Text(languageService.text(.profileEmail))
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

                    if vm.selectedPhotoData == nil {
                        ProfileIconPicker(selectedIcon: $vm.selectedProfileIcon)
                    }

                    TextField(languageService.text(.profilePseudoPlaceholder), text: $vm.pseudo)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    Toggle(isOn: $vm.acceptsTerms) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("J'accepte les règles de Torpille")
                                .font(.subheadline.weight(.semibold))
                            Text("Tolérance zéro pour le harcèlement, les contenus sexuels explicites, les menaces, le spam et les contenus abusifs. Les contenus signalés peuvent être supprimés et les comptes fautifs suspendus.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }
                .padding(18)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

                Button {
                    vm.save(onDone: onDone)
                } label: {
                    IllustratedActionButton(
                        title: vm.isSaving ? languageService.text(.saving) : languageService.text(.profileContinue),
                        subtitle: languageService.text(.profileContinueSubtitle),
                        systemImage: "arrow.right.circle.fill",
                        illustrationSymbol: "checkmark.seal.fill",
                        accent: .meadow
                    )
                }
                .buttonStyle(.plain)
                .disabled(vm.isSaving || !vm.canSubmitProfile)

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
