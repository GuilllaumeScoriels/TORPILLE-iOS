import SwiftUI

struct AuthScreen: View {
    @StateObject private var vm: AuthViewModel
    @State private var isPreparingSignUp = false
    @State private var presentedLegalDocument: LegalDocument?
    @State private var legalAcceptance = LegalAcceptanceDraft()
    @State private var hasContinuedFromLegal = false
    @State private var hasReadEULA = false
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
        Group {
            if hasContinuedFromLegal && legalAcceptance.canContinue {
                authenticationForm
            } else {
                legalWelcomePage
            }
        }
        .navigationTitle("Torpille")
        .sheet(item: $presentedLegalDocument) { document in
            LegalDocumentSheet(document: document, languageService: languageService) {
                hasReadEULA = true
                legalAcceptance.acceptsEULA = true
                presentedLegalDocument = nil
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var legalWelcomePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Image("TorpilleLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                Text(languageService.phrase("Avant de rejoindre Torpille"))
                    .font(.largeTitle.bold())
                Text(languageService.phrase("Lis et accepte les règles EULA et la politique de confidentialité pour accéder à la connexion ou à la création de compte."))
                    .foregroundStyle(.secondary)
                Picker(languageService.text(.appLanguage), selection: $languageService.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.nativeLabel).tag(language)
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    authLegalDocumentButton(document: .eula, isAccepted: legalAcceptance.acceptsEULA)
                    Toggle(languageService.phrase("J’accepte les règles EULA"), isOn: $legalAcceptance.acceptsEULA)
                        .disabled(!hasReadEULA)
                }
                .padding(18)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))

                VStack(alignment: .leading, spacing: 14) {
                    Link(destination: AppExternalLinks.privacyPolicy(language: languageService.effectiveLanguage)) {
                        Label(languageService.phrase("Lire la politique de confidentialité"), systemImage: "arrow.up.right.square")
                    }
                    Toggle(languageService.phrase("J’accepte la politique de confidentialité"), isOn: $legalAcceptance.acceptsPrivacyPolicy)
                }
                .padding(18)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))

                Text(languageService.phrase("Les deux acceptations sont obligatoires pour continuer."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    guard DeviceLegalAcceptance.record(legalAcceptance) else { return }
                    hasContinuedFromLegal = true
                } label: {
                    Text(languageService.phrase("Continuer"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!legalAcceptance.canContinue)
            }
            .padding(24)
        }
        .background(Color(.systemBackground))
    }

    private var authenticationForm: some View {
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
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        .textCase(nil)
                        .submitLabel(.next)
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    SecureField(languageService.text(.authPasswordPlaceholder), text: $vm.password)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .onSubmit {
                            vm.signIn(hasAcceptedRequiredDocuments: acceptsRequiredDocuments, onSuccess: onSignedIn)
                        }
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    if isPreparingSignUp {
                        SecureField(languageService.text(.authConfirmPasswordPlaceholder), text: $vm.passwordConfirmation)
                            .textContentType(.newPassword)
                            .submitLabel(.done)
                            .onSubmit {
                                vm.signUp(hasAcceptedRequiredDocuments: acceptsRequiredDocuments, onSuccess: onSignedUp)
                            }
                            .padding()
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .transition(.opacity.combined(with: .move(edge: .top)))

                    }
                }
                .padding(18)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

                Button(languageService.phrase("Revoir mes acceptations")) {
                    hasContinuedFromLegal = false
                }

                HStack(spacing: 18) {
                    Link(destination: AppExternalLinks.privacyPolicy(language: languageService.effectiveLanguage)) {
                        Label(languageService.phrase("Politique de confidentialité"), systemImage: "hand.raised.fill")
                    }
                    Link(destination: AppExternalLinks.support) {
                        Label(languageService.phrase("Support et contact"), systemImage: "envelope.fill")
                    }
                }
                .font(.footnote.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    vm.signIn(hasAcceptedRequiredDocuments: acceptsRequiredDocuments, onSuccess: onSignedIn)
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
                .disabled(vm.isLoading || !acceptsRequiredDocuments)

                Button {
                    if isPreparingSignUp {
                        vm.signUp(hasAcceptedRequiredDocuments: acceptsRequiredDocuments, onSuccess: onSignedUp)
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isPreparingSignUp = true
                        }
                    }
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
                .disabled(vm.isLoading || !acceptsRequiredDocuments)

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
                    // AuthViewModel already creates this text in the selected language.
                    Text(info)
                        .foregroundStyle(.green)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                if let error = vm.error {
                    // AuthViewModel maps Firebase Auth errors to the selected language.
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

    private var acceptsRequiredDocuments: Bool {
        hasContinuedFromLegal && legalAcceptance.canContinue && DeviceLegalAcceptance.hasAcceptedCurrentVersion
    }

    private func authLegalDocumentButton(document: LegalDocument, isAccepted: Bool) -> some View {
        Button { presentedLegalDocument = document } label: {
            HStack(spacing: 12) {
                Image(systemName: isAccepted ? "checkmark.seal.fill" : "doc.text.fill")
                    .foregroundStyle(isAccepted ? .green : ActionAccent.ocean.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(document.localizedTitle(languageService.effectiveLanguage))
                        .font(.subheadline.weight(.semibold))
                    Text(languageService.phrase(isAccepted ? "Lu et accepté" : "Ouvrir et accepter"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private enum LegalDocument: String, Identifiable {
    case eula
    var id: String { rawValue }

    func localizedTitle(_ language: AppLanguage) -> String {
        switch language {
        case .english: return "EULA rules"
        case .spanish: return "Reglas EULA"
        case .german: return "EULA-Regeln"
        case .italian: return "Regole EULA"
        case .portuguese: return "Regras EULA"
        case .system, .french: return "Règles EULA"
        }
    }

    func localizedParagraphs(_ language: AppLanguage) -> [String] {
        switch language {
        case .english: return [
            "By creating a Torpille account, you receive a personal, limited, revocable and non-transferable right to use the app in accordance with its features and these terms.",
            "You are responsible for keeping your credentials confidential, for the accuracy of your profile and for activity performed through your account. You must not bypass app protections, disrupt the service or use Torpille unlawfully.",
            "You remain responsible for content you publish and confirm that you have the rights required to share it. You grant Torpille the technical rights necessary to host, display and moderate that content within the app.",
            "Torpille may remove content, restrict features, suspend or close an account that violates these EULA rules, the law or another person's rights. You may stop using the service and request account deletion in the app settings.",
            "Torpille does not allow objectionable content or abusive behavior. Explicit sexual content, child exploitation, harassment, threats, hate speech, violence, impersonation, spam and unlawful use are prohibited.",
            "You must respect other users. Do not intimidate, target or humiliate anyone, publish private information without permission, or encourage dangerous behavior.",
            "You can report content or accounts and immediately block a user. Reports are reviewed promptly; affected content may be filtered, hidden, quarantined or removed.",
            "Users who break these rules may have content removed and accounts suspended or permanently banned. Torpille applies this policy without exception to objectionable content and abusive users."
        ]
        case .spanish: return [
            "Al crear una cuenta de Torpille, recibes un derecho personal, limitado, revocable e intransferible para usar la aplicación de acuerdo con sus funciones y estas condiciones.",
            "Eres responsable de mantener la confidencialidad de tus credenciales, de la exactitud de tu perfil y de la actividad realizada desde tu cuenta. No debes eludir las protecciones, perturbar el servicio ni usar Torpille ilegalmente.",
            "Sigues siendo responsable del contenido que publicas y confirmas que tienes los derechos necesarios para compartirlo. Concedes a Torpille los derechos técnicos necesarios para alojarlo, mostrarlo y moderarlo.",
            "Torpille puede retirar contenido, limitar funciones, suspender o cerrar una cuenta que infrinja este acuerdo, las reglas, la ley o los derechos de terceros. Puedes dejar el servicio y solicitar la eliminación de tu cuenta en los ajustes.",
            "Torpille no permite contenido objetable ni conductas abusivas. Se prohíben el contenido sexual explícito, la explotación infantil, el acoso, las amenazas, el odio, la violencia, la suplantación, el spam y el uso ilegal.",
            "Debes respetar a los demás usuarios. No intimides, ataques ni humilles a nadie, no publiques información privada sin permiso ni fomentes conductas peligrosas.",
            "Puedes denunciar contenido o cuentas y bloquear inmediatamente a un usuario. Las denuncias se revisan rápidamente y el contenido puede filtrarse, ocultarse, ponerse en cuarentena o eliminarse.",
            "Quienes incumplan estas reglas pueden perder su contenido y ver su cuenta suspendida o expulsada permanentemente."
        ]
        case .german: return [
            "Mit der Erstellung eines Torpille-Kontos erhältst du ein persönliches, beschränktes, widerrufliches und nicht übertragbares Recht, die App gemäß ihren Funktionen und diesen Bedingungen zu nutzen.",
            "Du bist für die Vertraulichkeit deiner Zugangsdaten, die Richtigkeit deines Profils und alle Aktivitäten über dein Konto verantwortlich. Schutzmaßnahmen dürfen nicht umgangen und der Dienst nicht gestört oder rechtswidrig genutzt werden.",
            "Für veröffentlichte Inhalte bleibst du verantwortlich und bestätigst, dass du die nötigen Rechte besitzt. Du gewährst Torpille die technischen Rechte, die zum Hosten, Anzeigen und Moderieren erforderlich sind.",
            "Torpille kann Inhalte entfernen, Funktionen einschränken und Konten sperren oder schließen, wenn diese EULA-Regeln, Gesetze oder Rechte Dritter verletzt werden.",
            "Torpille erlaubt keine anstößigen Inhalte oder missbräuchliches Verhalten. Explizit sexuelle Inhalte, Ausbeutung Minderjähriger, Belästigung, Drohungen, Hassrede, Gewalt, Identitätsmissbrauch, Spam und rechtswidrige Nutzung sind verboten.",
            "Respektiere andere Nutzer. Niemand darf eingeschüchtert, gezielt angegriffen oder gedemütigt werden. Private Informationen dürfen nicht ohne Erlaubnis veröffentlicht und gefährliches Verhalten nicht gefördert werden.",
            "Du kannst Inhalte oder Konten melden und Nutzer sofort blockieren. Meldungen werden zeitnah geprüft; Inhalte können gefiltert, verborgen, isoliert oder entfernt werden.",
            "Bei Regelverstößen können Inhalte entfernt und Konten vorübergehend oder dauerhaft gesperrt werden."
        ]
        case .italian: return [
            "Creando un account Torpille, ricevi un diritto personale, limitato, revocabile e non trasferibile di usare l'app secondo le sue funzionalità e queste condizioni.",
            "Sei responsabile della riservatezza delle credenziali, dell'esattezza del profilo e delle attività svolte dal tuo account. Non devi aggirare le protezioni, disturbare il servizio o usare Torpille illegalmente.",
            "Resti responsabile dei contenuti pubblicati e confermi di avere i diritti necessari per condividerli. Concedi a Torpille i diritti tecnici necessari per ospitarli, mostrarli e moderarli.",
            "Torpille può rimuovere contenuti, limitare funzioni, sospendere o chiudere account che violano questo accordo, le regole, la legge o i diritti altrui.",
            "Torpille non consente contenuti discutibili o comportamenti abusivi. Sono vietati contenuti sessuali espliciti, sfruttamento di minori, molestie, minacce, odio, violenza, furto d'identità, spam e usi illegali.",
            "Devi rispettare gli altri utenti. Non intimidire, prendere di mira o umiliare nessuno, non pubblicare informazioni private senza permesso e non incoraggiare comportamenti pericolosi.",
            "Puoi segnalare contenuti o account e bloccare subito un utente. Le segnalazioni vengono esaminate rapidamente; i contenuti possono essere filtrati, nascosti, messi in quarantena o rimossi.",
            "Chi viola queste regole può vedere rimossi i propri contenuti e l'account sospeso o escluso definitivamente."
        ]
        case .portuguese: return [
            "Ao criar uma conta Torpille, você recebe um direito pessoal, limitado, revogável e intransferível de usar o app conforme seus recursos e estes termos.",
            "Você é responsável pela confidencialidade das credenciais, pela exatidão do perfil e pelas atividades realizadas na conta. Não deve contornar proteções, prejudicar o serviço nem usar o Torpille ilegalmente.",
            "Você continua responsável pelo conteúdo publicado e confirma possuir os direitos necessários para compartilhá-lo. Concede ao Torpille os direitos técnicos necessários para hospedá-lo, exibi-lo e moderá-lo.",
            "O Torpille pode remover conteúdo, limitar recursos, suspender ou encerrar contas que violem este acordo, as regras, a lei ou direitos de terceiros.",
            "O Torpille não permite conteúdo impróprio nem comportamento abusivo. Conteúdo sexual explícito, exploração de menores, assédio, ameaças, ódio, violência, falsidade ideológica, spam e uso ilegal são proibidos.",
            "Respeite os outros usuários. Não intimide, persiga ou humilhe ninguém, não publique informações privadas sem permissão nem incentive comportamentos perigosos.",
            "Você pode denunciar conteúdo ou contas e bloquear imediatamente um usuário. As denúncias são analisadas rapidamente; o conteúdo pode ser filtrado, ocultado, colocado em quarentena ou removido.",
            "Quem violar estas regras poderá ter conteúdo removido e a conta suspensa ou banida permanentemente."
        ]
        case .system, .french: return [
            "En créant un compte Torpille, tu obtiens un droit personnel, limité, révocable et non transférable d'utiliser l'application conformément à ses fonctionnalités et aux présentes conditions.",
            "Tu es responsable de la confidentialité de tes identifiants, de l'exactitude des informations de ton profil et de toute activité réalisée depuis ton compte. Tu ne dois pas contourner les protections, perturber le service ou utiliser Torpille à des fins illégales.",
            "Les contenus que tu publies restent sous ta responsabilité. Tu garantis disposer des droits nécessaires pour les partager et accordes à Torpille les droits techniques indispensables à leur hébergement, leur affichage et leur modération.",
            "Torpille peut retirer un contenu, limiter une fonctionnalité, suspendre ou fermer un compte en cas de violation de ces règles EULA, de la loi ou des droits d'autrui.",
            "Torpille n'autorise aucun contenu répréhensible ni comportement abusif. Sont notamment interdits : les contenus sexuels explicites, l'exploitation de mineurs, le harcèlement, les menaces, les discours haineux, la violence, l'usurpation d'identité, le spam et toute utilisation illégale.",
            "Tu dois respecter les autres utilisateurs. Il est interdit d'intimider, de cibler ou d'humilier une personne, de publier ses informations privées sans autorisation ou d'encourager un comportement dangereux.",
            "Tu peux signaler un contenu ou un compte et bloquer immédiatement un utilisateur. Les signalements sont examinés rapidement ; les contenus concernés peuvent être filtrés, masqués, mis en quarantaine ou supprimés.",
            "Tout utilisateur qui enfreint ces règles peut voir son contenu supprimé et son compte suspendu ou définitivement exclu."
        ]
        }
    }
}

private struct LegalDocumentSheet: View {
    @Environment(\.dismiss) private var dismiss
    let document: LegalDocument
    @ObservedObject var languageService: AppLanguageService
    let onAccept: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label(title, systemImage: "doc.text.fill")
                        .font(.title2.bold())
                        .foregroundStyle(ActionAccent.ocean.tint)

                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(languageService.phrase(paragraph))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Divider()

                    Text(acceptanceNotice)
                        .font(.headline)

                    Button(action: onAccept) {
                        Label(acceptLabel, systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(closeLabel) { dismiss() }
                }
            }
        }
    }

    private var paragraphs: [String] {
        document.localizedParagraphs(languageService.effectiveLanguage)
    }

    private var title: String { document.localizedTitle(languageService.effectiveLanguage) }

    private var acceptanceNotice: String {
        switch languageService.effectiveLanguage {
        case .english: return "By tapping Accept, you confirm that you have read and accepted this document."
        case .spanish: return "Al pulsar Aceptar, confirmas que has leído y aceptado este documento."
        case .german: return "Mit Akzeptieren bestätigst du, dass du dieses Dokument gelesen und angenommen hast."
        case .italian: return "Toccando Accetta, confermi di aver letto e accettato questo documento."
        case .portuguese: return "Ao tocar em Aceitar, você confirma que leu e aceitou este documento."
        case .system, .french: return "En appuyant sur Accepter, tu confirmes avoir lu et accepté ce document."
        }
    }

    private var acceptLabel: String {
        switch languageService.effectiveLanguage {
        case .english: return "Accept"
        case .spanish: return "Aceptar"
        case .german: return "Akzeptieren"
        case .italian: return "Accetta"
        case .portuguese: return "Aceitar"
        case .system, .french: return "Accepter"
        }
    }

    private var closeLabel: String {
        switch languageService.effectiveLanguage {
        case .english: return "Close"
        case .spanish: return "Cerrar"
        case .german: return "Schließen"
        case .italian: return "Chiudi"
        case .portuguese: return "Fechar"
        case .system, .french: return "Fermer"
        }
    }
}

struct ProfileSetupScreen: View {
    @StateObject private var vm: ProfileViewModel
    @State private var presentedLegalDocument: LegalDocument?
    @State private var isShowingAccountDeletionConfirmation = false
    @ObservedObject private var languageService: AppLanguageService
    let onDone: () -> Void
    let onBack: () -> Void

    init(onDone: @escaping () -> Void, onBack: @escaping () -> Void, env: AppEnvironment) {
        self.onDone = onDone
        self.onBack = onBack
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

                    Text(languageService.phrase("Informations obligatoires"))
                        .font(.headline)

                    TextField(languageService.phrase("Prénom"), text: $vm.firstName)
                        .textContentType(.givenName)
                        .textInputAutocapitalization(.words)
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    TextField(languageService.phrase("Nom de famille"), text: $vm.lastName)
                        .textContentType(.familyName)
                        .textInputAutocapitalization(.words)
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    TextField(languageService.text(.profilePseudoPlaceholder), text: $vm.pseudo)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    Text(languageService.phrase("Informations facultatives"))
                        .font(.headline)

                    ProfileSexPicker(selection: $vm.sex)

                    Toggle(languageService.phrase("Ajouter ma date de naissance"), isOn: Binding(
                        get: { vm.birthDate != nil },
                        set: { vm.birthDate = $0 ? Calendar.current.date(byAdding: .year, value: -18, to: Date()) : nil }
                    ))

                    if vm.birthDate != nil {
                        DatePicker(
                            languageService.phrase("Date de naissance"),
                            selection: Binding(get: { vm.birthDate ?? Date() }, set: { vm.birthDate = $0 }),
                            in: ...Date(),
                            displayedComponents: .date
                        )
                    }

                    TextField(languageService.phrase("Ville de domiciliation"), text: $vm.city)
                        .textContentType(.addressCity)
                        .textInputAutocapitalization(.words)
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    TextField(languageService.phrase("Courte présentation"), text: $vm.bio, axis: .vertical)
                        .lineLimit(2...4)
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    Text(legalSectionTitle)
                        .font(.headline)

                    legalDocumentButton(document: .eula, isAccepted: vm.acceptsEULA)
                    Label(languageService.phrase("Politique de confidentialité"), systemImage: vm.acceptsPrivacyPolicy ? "checkmark.seal.fill" : "hand.raised.fill")
                        .foregroundStyle(vm.acceptsPrivacyPolicy ? Color.green : Color.secondary)

                    if !vm.acceptsRequiredDocuments {
                        Text(legalRequirementText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(18)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

                HStack(spacing: 18) {
                    Link(destination: AppExternalLinks.privacyPolicy(language: languageService.effectiveLanguage)) {
                        Label(languageService.phrase("Politique de confidentialité"), systemImage: "hand.raised.fill")
                    }
                    Link(destination: AppExternalLinks.support) {
                        Label(languageService.phrase("Support et contact"), systemImage: "envelope.fill")
                    }
                }
                .font(.footnote.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

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
                .disabled(vm.isSaving || vm.isDeletingAccount || !vm.canSubmitProfile)

                if let error = vm.error {
                    Text(languageService.localizedRuntimeMessage(error))
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
        .navigationTitle(languageService.text(.profile))
        .task {
            await vm.loadExistingProfile()
        }
        .sheet(item: $presentedLegalDocument) { document in
            LegalDocumentSheet(document: document, languageService: languageService) {
                vm.acceptEULA()
                presentedLegalDocument = nil
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .iosBackSwipe {
            isShowingAccountDeletionConfirmation = true
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(languageService.phrase("Retour")) {
                    isShowingAccountDeletionConfirmation = true
                }
                .disabled(vm.isSaving || vm.isDeletingAccount)
                .accessibilityLabel(languageService.phrase("Retour"))
            }
        }
        .alert(cancelAccountTitle, isPresented: $isShowingAccountDeletionConfirmation) {
            Button(languageService.phrase("Annuler"), role: .cancel) {}
            Button(languageService.text(.deleteAccount), role: .destructive) {
                vm.deleteIncompleteAccount(onDone: onBack)
            }
        } message: {
            Text(cancelAccountMessage)
        }
        .overlay {
            if vm.isDeletingAccount {
                ZStack {
                    Color.black.opacity(0.12).ignoresSafeArea()
                    TorpilleLoadingView(languageService.text(.deleteAccountProgress))
                        .padding()
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    private func legalDocumentButton(document: LegalDocument, isAccepted: Bool) -> some View {
        Button { presentedLegalDocument = document } label: {
            HStack(spacing: 12) {
                Image(systemName: isAccepted ? "checkmark.seal.fill" : "doc.text.magnifyingglass")
                    .foregroundStyle(isAccepted ? Color.green : ActionAccent.ocean.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(document.localizedTitle(languageService.effectiveLanguage))
                        .font(.subheadline.weight(.semibold))
                    Text(isAccepted ? acceptedLabel : readToAcceptLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var legalSectionTitle: String {
        switch languageService.effectiveLanguage {
        case .english: return "Required agreements"
        case .spanish: return "Acuerdos obligatorios"
        case .german: return "Erforderliche Zustimmungen"
        case .italian: return "Accordi obbligatori"
        case .portuguese: return "Aceites obrigatórios"
        case .system, .french: return "Acceptations obligatoires"
        }
    }

    private var acceptedLabel: String {
        switch languageService.effectiveLanguage {
        case .english: return "Read and accepted"
        case .spanish: return "Leído y aceptado"
        case .german: return "Gelesen und akzeptiert"
        case .italian: return "Letto e accettato"
        case .portuguese: return "Lido e aceito"
        case .system, .french: return "Lu et accepté"
        }
    }

    private var readToAcceptLabel: String {
        switch languageService.effectiveLanguage {
        case .english: return "Open and scroll to accept"
        case .spanish: return "Abrir y desplazarse para aceptar"
        case .german: return "Öffnen und zum Akzeptieren scrollen"
        case .italian: return "Apri e scorri per accettare"
        case .portuguese: return "Abra e role para aceitar"
        case .system, .french: return "Ouvrir et faire défiler pour accepter"
        }
    }

    private var legalRequirementText: String {
        switch languageService.effectiveLanguage {
        case .english: return "Read and accept both documents before continuing."
        case .spanish: return "Lee y acepta ambos documentos antes de continuar."
        case .german: return "Lies und akzeptiere beide Dokumente, bevor du fortfährst."
        case .italian: return "Leggi e accetta entrambi i documenti prima di continuare."
        case .portuguese: return "Leia e aceite os dois documentos antes de continuar."
        case .system, .french: return "Lis et accepte les deux documents avant de continuer."
        }
    }

    private var cancelAccountTitle: String {
        switch languageService.effectiveLanguage {
        case .english: return "Cancel account creation?"
        case .spanish: return "¿Cancelar la creación de la cuenta?"
        case .german: return "Kontoerstellung abbrechen?"
        case .italian: return "Annullare la creazione dell'account?"
        case .portuguese: return "Cancelar a criação da conta?"
        case .system, .french: return "Annuler la création du compte ?"
        }
    }

    private var cancelAccountMessage: String {
        switch languageService.effectiveLanguage {
        case .english: return "Your account and all associated data will be deleted. Reusing this email will require a new email verification."
        case .spanish: return "Tu cuenta y todos los datos asociados se eliminarán. Si reutilizas este correo, tendrás que verificarlo de nuevo."
        case .german: return "Dein Konto und alle zugehörigen Daten werden gelöscht. Bei erneuter Verwendung dieser E-Mail ist eine neue Bestätigung erforderlich."
        case .italian: return "Il tuo account e tutti i dati associati verranno eliminati. Riutilizzando questa email dovrai verificarla di nuovo."
        case .portuguese: return "Sua conta e todos os dados associados serão excluídos. Ao reutilizar este email, será necessária uma nova verificação."
        case .system, .french: return "Ton compte et toutes les données associées seront supprimés. Si tu réutilises cet email, tu devras le vérifier à nouveau."
        }
    }
}
