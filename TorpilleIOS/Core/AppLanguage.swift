import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case french
    case english
    case spanish
    case german
    case italian
    case portuguese

    var id: String { rawValue }

    var localeIdentifier: String {
        switch self {
        case .system:
            return Locale.current.identifier
        case .french:
            return "fr"
        case .english:
            return "en"
        case .spanish:
            return "es"
        case .german:
            return "de"
        case .italian:
            return "it"
        case .portuguese:
            return "pt"
        }
    }

    var nativeLabel: String {
        switch self {
        case .system: return "System"
        case .french: return "Français"
        case .english: return "English"
        case .spanish: return "Español"
        case .german: return "Deutsch"
        case .italian: return "Italiano"
        case .portuguese: return "Português"
        }
    }
}

enum AppTextKey {
    case home
    case communities
    case profile
    case leaderboard
    case map
    case reels
    case profileTitle
    case saveProfile
    case saving
    case resetPassword
    case viewGlobalLeaderboard
    case signOut
    case deleteAccount
    case deleteAccountProgress
    case language
    case reelsTitle
    case reelsSubtitle
    case noReelsTitle
    case noReelsDescription
    case savedReelsCommunity
    case publishToReels
    case publishedBadge
    case appLanguage
    case authWelcomeTitle
    case authWelcomeSubtitle
    case authSectionTitle
    case authSectionSubtitle
    case authEmailPlaceholder
    case authPasswordPlaceholder
    case authSignIn
    case authSignInSubtitle
    case authSignUp
    case authSignUpSubtitle
    case authForgotPassword
    case authForgotPasswordSubtitle
    case authLoading
    case profileSetupTitle
    case profileSetupSubtitle
    case profileEmail
    case profilePseudoPlaceholder
    case profileContinue
    case profileContinueSubtitle
    case authVerificationNoticeTitle
    case authVerificationNoticeSubtitle
}

@MainActor
final class AppLanguageService: ObservableObject {
    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: storageKey)
        }
    }

    private let storageKey = "torpille.appLanguage"

    init() {
        let stored = UserDefaults.standard.string(forKey: storageKey)
        language = AppLanguage(rawValue: stored ?? "") ?? .system
    }

    var effectiveLanguage: AppLanguage {
        switch language {
        case .system:
            let code = String(Locale.preferredLanguages.first?.prefix(2) ?? "fr")
            switch code {
            case "en": return .english
            case "es": return .spanish
            case "de": return .german
            case "it": return .italian
            case "pt": return .portuguese
            default: return .french
            }
        default:
            return language
        }
    }

    var locale: Locale {
        Locale(identifier: language.localeIdentifier)
    }

    var firebaseAuthLanguageCode: String {
        effectiveLanguage.localeIdentifier
    }

    func text(_ key: AppTextKey) -> String {
        switch effectiveLanguage {
        case .system, .french:
            return french(key)
        case .english:
            return english(key)
        case .spanish:
            return spanish(key)
        case .german:
            return german(key)
        case .italian:
            return italian(key)
        case .portuguese:
            return portuguese(key)
        }
    }

    func localizedResetPasswordInfo(for email: String) -> String {
        switch effectiveLanguage {
        case .system, .french:
            return "Un email de réinitialisation a été envoyé à \(email)."
        case .english:
            return "A password reset email has been sent to \(email)."
        case .spanish:
            return "Se ha enviado un correo de restablecimiento a \(email)."
        case .german:
            return "Eine E-Mail zum Zurücksetzen des Passworts wurde an \(email) gesendet."
        case .italian:
            return "Un'email per reimpostare la password è stata inviata a \(email)."
        case .portuguese:
            return "Um email de redefinição de senha foi enviado para \(email)."
        }
    }

    func localizedResetPasswordPrompt() -> String {
        switch effectiveLanguage {
        case .system, .french:
            return "Renseigne ton email pour recevoir le lien de réinitialisation."
        case .english:
            return "Enter your email to receive the reset link."
        case .spanish:
            return "Introduce tu correo para recibir el enlace de restablecimiento."
        case .german:
            return "Gib deine E-Mail ein, um den Zurücksetzungslink zu erhalten."
        case .italian:
            return "Inserisci la tua email per ricevere il link di reimpostazione."
        case .portuguese:
            return "Informe seu email para receber o link de redefinição."
        }
    }

    func localizedVerificationEmailSent(to email: String) -> String {
        switch effectiveLanguage {
        case .system, .french:
            return "Un email de vérification a été envoyé à \(email). Confirme ton adresse avant de te connecter. Pense aussi à vérifier tes spams."
        case .english:
            return "A verification email has been sent to \(email). Confirm your address before signing in. Also check your spam folder."
        case .spanish:
            return "Se ha enviado un correo de verificación a \(email). Confirma tu dirección antes de iniciar sesión. Revisa también tu carpeta de spam."
        case .german:
            return "Eine Bestätigungs-E-Mail wurde an \(email) gesendet. Bestätige deine Adresse, bevor du dich anmeldest. Prüfe auch deinen Spam-Ordner."
        case .italian:
            return "Un'email di verifica è stata inviata a \(email). Conferma il tuo indirizzo prima di accedere. Controlla anche la cartella spam."
        case .portuguese:
            return "Um email de verificação foi enviado para \(email). Confirme seu endereço antes de entrar. Verifique também sua pasta de spam."
        }
    }

    func localizedEmailNotVerified(for email: String) -> String {
        switch effectiveLanguage {
        case .system, .french:
            return "Ton email \(email) n'est pas encore vérifié. Un nouveau lien de confirmation vient d'être envoyé."
        case .english:
            return "Your email \(email) is not verified yet. A new confirmation link has just been sent."
        case .spanish:
            return "Tu correo \(email) aún no está verificado. Se acaba de enviar un nuevo enlace de confirmación."
        case .german:
            return "Deine E-Mail \(email) ist noch nicht bestätigt. Ein neuer Bestätigungslink wurde gerade gesendet."
        case .italian:
            return "La tua email \(email) non è ancora verificata. È stato appena inviato un nuovo link di conferma."
        case .portuguese:
            return "Seu email \(email) ainda não foi verificado. Um novo link de confirmação foi enviado agora."
        }
    }

    func localizedVerificationEmailPrompt() -> String {
        switch effectiveLanguage {
        case .system, .french:
            return "Vérifie ton email avant d'accéder à l'application."
        case .english:
            return "Verify your email before accessing the app."
        case .spanish:
            return "Verifica tu correo antes de acceder a la aplicación."
        case .german:
            return "Bestätige deine E-Mail, bevor du auf die App zugreifst."
        case .italian:
            return "Verifica la tua email prima di accedere all'app."
        case .portuguese:
            return "Verifique seu email antes de acessar o app."
        }
    }

    func localizedNotificationBody(for message: NotificationMessageDescriptor) -> String {
        let sender = message.sender.isEmpty ? localizedSomeone() : message.sender

        switch effectiveLanguage {
        case .system, .french:
            switch message.type {
            case .text:
                let snippet = message.snippet?.isEmpty == false ? message.snippet! : "Nouveau message"
                return "\(sender) : \(snippet)"
            case .audio:
                return "\(sender) a envoyé un vocal."
            case .image:
                return "\(sender) a envoyé une image."
            case .video:
                if let tagged = message.taggedPseudo, !tagged.isEmpty {
                    return "\(sender) a envoyé une vidéo pour \(tagged)."
                }
                return "\(sender) a envoyé une vidéo."
            case .other:
                return "\(sender) a envoyé un nouveau contenu."
            }
        case .english:
            switch message.type {
            case .text:
                let snippet = message.snippet?.isEmpty == false ? message.snippet! : "New message"
                return "\(sender): \(snippet)"
            case .audio:
                return "\(sender) sent a voice message."
            case .image:
                return "\(sender) sent an image."
            case .video:
                if let tagged = message.taggedPseudo, !tagged.isEmpty {
                    return "\(sender) sent a video for \(tagged)."
                }
                return "\(sender) sent a video."
            case .other:
                return "\(sender) sent new content."
            }
        case .spanish:
            switch message.type {
            case .text:
                let snippet = message.snippet?.isEmpty == false ? message.snippet! : "Nuevo mensaje"
                return "\(sender): \(snippet)"
            case .audio:
                return "\(sender) envió un mensaje de voz."
            case .image:
                return "\(sender) envió una imagen."
            case .video:
                if let tagged = message.taggedPseudo, !tagged.isEmpty {
                    return "\(sender) envió un video para \(tagged)."
                }
                return "\(sender) envió un video."
            case .other:
                return "\(sender) envió nuevo contenido."
            }
        case .german:
            switch message.type {
            case .text:
                let snippet = message.snippet?.isEmpty == false ? message.snippet! : "Neue Nachricht"
                return "\(sender): \(snippet)"
            case .audio:
                return "\(sender) hat eine Sprachnachricht gesendet."
            case .image:
                return "\(sender) hat ein Bild gesendet."
            case .video:
                if let tagged = message.taggedPseudo, !tagged.isEmpty {
                    return "\(sender) hat ein Video für \(tagged) gesendet."
                }
                return "\(sender) hat ein Video gesendet."
            case .other:
                return "\(sender) hat neue Inhalte gesendet."
            }
        case .italian:
            switch message.type {
            case .text:
                let snippet = message.snippet?.isEmpty == false ? message.snippet! : "Nuovo messaggio"
                return "\(sender): \(snippet)"
            case .audio:
                return "\(sender) ha inviato un messaggio vocale."
            case .image:
                return "\(sender) ha inviato un'immagine."
            case .video:
                if let tagged = message.taggedPseudo, !tagged.isEmpty {
                    return "\(sender) ha inviato un video per \(tagged)."
                }
                return "\(sender) ha inviato un video."
            case .other:
                return "\(sender) ha inviato un nuovo contenuto."
            }
        case .portuguese:
            switch message.type {
            case .text:
                let snippet = message.snippet?.isEmpty == false ? message.snippet! : "Nova mensagem"
                return "\(sender): \(snippet)"
            case .audio:
                return "\(sender) enviou uma mensagem de voz."
            case .image:
                return "\(sender) enviou uma imagem."
            case .video:
                if let tagged = message.taggedPseudo, !tagged.isEmpty {
                    return "\(sender) enviou um vídeo para \(tagged)."
                }
                return "\(sender) enviou um vídeo."
            case .other:
                return "\(sender) enviou novo conteúdo."
            }
        }
    }

    func localizedTorpilleNotificationBody(from sender: String) -> String {
        let resolvedSender = sender.isEmpty ? localizedSomeone() : sender
        switch effectiveLanguage {
        case .system, .french:
            return "Torpille pour toi de \(resolvedSender)."
        case .english:
            return "Torpille for you from \(resolvedSender)."
        case .spanish:
            return "Torpille para ti de \(resolvedSender)."
        case .german:
            return "Torpille für dich von \(resolvedSender)."
        case .italian:
            return "Torpille per te da \(resolvedSender)."
        case .portuguese:
            return "Torpille para você de \(resolvedSender)."
        }
    }

    private func localizedSomeone() -> String {
        switch effectiveLanguage {
        case .system, .french: return "Quelqu’un"
        case .english: return "Someone"
        case .spanish: return "Alguien"
        case .german: return "Jemand"
        case .italian: return "Qualcuno"
        case .portuguese: return "Alguém"
        }
    }

    private func french(_ key: AppTextKey) -> String {
        switch key {
        case .home: return "Accueil"
        case .communities: return "Communautés"
        case .profile: return "Profil"
        case .leaderboard: return "Classement"
        case .map: return "Carte"
        case .reels: return "Memories"
        case .profileTitle: return "Ton profil"
        case .saveProfile: return "Enregistrer les modifications"
        case .saving: return "Enregistrement…"
        case .resetPassword: return "Réinitialiser le mot de passe"
        case .viewGlobalLeaderboard: return "Voir le classement global"
        case .signOut: return "Déconnexion"
        case .deleteAccount: return "Supprimer mon compte"
        case .deleteAccountProgress: return "Suppression du compte…"
        case .language: return "Langue"
        case .reelsTitle: return "Memories"
        case .reelsSubtitle: return "Les torpilles que leurs auteurs ont choisi de partager avec toute l'app."
        case .noReelsTitle: return "Aucune memory publiée"
        case .noReelsDescription: return "Publie une torpille quand tu veux la montrer au monde."
        case .savedReelsCommunity: return "Communauté"
        case .publishToReels: return "Publier aussi dans Memories"
        case .publishedBadge: return "Publié"
        case .appLanguage: return "Langue de l'application"
        case .authWelcomeTitle: return "Bienvenue sur Torpille"
        case .authWelcomeSubtitle: return "Connecte-toi ou crée ton compte et repars directement dans l'action."
        case .authSectionTitle: return "Connexion"
        case .authSectionSubtitle: return "Entre tes identifiants pour rejoindre tes communautés."
        case .authEmailPlaceholder: return "Email"
        case .authPasswordPlaceholder: return "Mot de passe"
        case .authSignIn: return "Se connecter"
        case .authSignInSubtitle: return "Récupère ton compte et retrouve tes parties en quelques secondes."
        case .authSignUp: return "Créer un compte"
        case .authSignUpSubtitle: return "Clique ici si tu n'as pas encore de compte."
        case .authForgotPassword: return "Mot de passe oublié"
        case .authForgotPasswordSubtitle: return "Reçois un email pour reprendre l'accès à ton compte."
        case .authLoading: return "Chargement…"
        case .profileSetupTitle: return "Crée ton profil"
        case .profileSetupSubtitle: return "Ajoute une photo, choisis un pseudo et rends ton arrivée plus fun dès le premier écran."
        case .profileEmail: return "Email"
        case .profilePseudoPlaceholder: return "Pseudo"
        case .profileContinue: return "Continuer"
        case .profileContinueSubtitle: return "Valide ton profil pour entrer dans l'application."
        case .authVerificationNoticeTitle: return "Email à confirmer"
        case .authVerificationNoticeSubtitle: return "Après inscription, tu devras confirmer ton adresse email avant d'accéder à l'app."
        }
    }

    private func english(_ key: AppTextKey) -> String {
        switch key {
        case .home: return "Home"
        case .communities: return "Communities"
        case .profile: return "Profile"
        case .leaderboard: return "Leaderboard"
        case .map: return "Map"
        case .reels: return "Memories"
        case .profileTitle: return "Your profile"
        case .saveProfile: return "Save changes"
        case .saving: return "Saving…"
        case .resetPassword: return "Reset password"
        case .viewGlobalLeaderboard: return "View global leaderboard"
        case .signOut: return "Sign out"
        case .deleteAccount: return "Delete my account"
        case .deleteAccountProgress: return "Deleting account…"
        case .language: return "Language"
        case .reelsTitle: return "Memories"
        case .reelsSubtitle: return "Torpilles their creators chose to share with the whole app."
        case .noReelsTitle: return "No published reels"
        case .noReelsDescription: return "Publish a torpille whenever you want to show it to the world."
        case .savedReelsCommunity: return "Community"
        case .publishToReels: return "Also publish to Memories"
        case .publishedBadge: return "Published"
        case .appLanguage: return "App language"
        case .authWelcomeTitle: return "Welcome to Torpille"
        case .authWelcomeSubtitle: return "Sign in or create your account and jump straight back into the action."
        case .authSectionTitle: return "Sign in"
        case .authSectionSubtitle: return "Enter your credentials to join your communities."
        case .authEmailPlaceholder: return "Email"
        case .authPasswordPlaceholder: return "Password"
        case .authSignIn: return "Sign in"
        case .authSignInSubtitle: return "Get your account back and return to your games in seconds."
        case .authSignUp: return "Create an account"
        case .authSignUpSubtitle: return "Tap here if you don't have an account yet."
        case .authForgotPassword: return "Forgot password"
        case .authForgotPasswordSubtitle: return "Receive an email to recover access to your account."
        case .authLoading: return "Loading…"
        case .profileSetupTitle: return "Create your profile"
        case .profileSetupSubtitle: return "Add a photo, choose a username and make your arrival fun from the very first screen."
        case .profileEmail: return "Email"
        case .profilePseudoPlaceholder: return "Username"
        case .profileContinue: return "Continue"
        case .profileContinueSubtitle: return "Confirm your profile to enter the app."
        case .authVerificationNoticeTitle: return "Email confirmation required"
        case .authVerificationNoticeSubtitle: return "After signing up, you must confirm your email address before accessing the app."
        }
    }

    private func spanish(_ key: AppTextKey) -> String {
        switch key {
        case .home: return "Inicio"
        case .communities: return "Comunidades"
        case .profile: return "Perfil"
        case .leaderboard: return "Clasificación"
        case .map: return "Mapa"
        case .reels: return "Memories"
        case .profileTitle: return "Tu perfil"
        case .saveProfile: return "Guardar cambios"
        case .saving: return "Guardando…"
        case .resetPassword: return "Restablecer contraseña"
        case .viewGlobalLeaderboard: return "Ver clasificación global"
        case .signOut: return "Cerrar sesión"
        case .deleteAccount: return "Eliminar mi cuenta"
        case .deleteAccountProgress: return "Eliminando cuenta…"
        case .language: return "Idioma"
        case .reelsTitle: return "Memories"
        case .reelsSubtitle: return "Las mejores torpilles listas para volverse virales."
        case .noReelsTitle: return "No hay reels publicados"
        case .noReelsDescription: return "Publica una torpille cuando quieras mostrarla al mundo."
        case .savedReelsCommunity: return "Comunidad"
        case .publishToReels: return "Publicar también en Memories"
        case .publishedBadge: return "Publicado"
        case .appLanguage: return "Idioma de la app"
        case .authWelcomeTitle: return "Bienvenido a Torpille"
        case .authWelcomeSubtitle: return "Inicia sesión o crea tu cuenta y vuelve directamente a la acción."
        case .authSectionTitle: return "Conexión"
        case .authSectionSubtitle: return "Introduce tus credenciales para unirte a tus comunidades."
        case .authEmailPlaceholder: return "Correo electrónico"
        case .authPasswordPlaceholder: return "Contraseña"
        case .authSignIn: return "Iniciar sesión"
        case .authSignInSubtitle: return "Recupera tu cuenta y vuelve a tus partidas en segundos."
        case .authSignUp: return "Crear una cuenta"
        case .authSignUpSubtitle: return "Pulsa aquí si todavía no tienes una cuenta."
        case .authForgotPassword: return "Olvidé mi contraseña"
        case .authForgotPasswordSubtitle: return "Recibe un correo para recuperar el acceso a tu cuenta."
        case .authLoading: return "Cargando…"
        case .profileSetupTitle: return "Crea tu perfil"
        case .profileSetupSubtitle: return "Añade una foto, elige un apodo y haz tu llegada más divertida desde la primera pantalla."
        case .profileEmail: return "Correo electrónico"
        case .profilePseudoPlaceholder: return "Apodo"
        case .profileContinue: return "Continuar"
        case .profileContinueSubtitle: return "Valida tu perfil para entrar en la app."
        case .authVerificationNoticeTitle: return "Email por confirmar"
        case .authVerificationNoticeSubtitle: return "Después del registro, deberás confirmar tu correo antes de acceder a la app."
        }
    }

    private func german(_ key: AppTextKey) -> String {
        switch key {
        case .home: return "Start"
        case .communities: return "Communitys"
        case .profile: return "Profil"
        case .leaderboard: return "Rangliste"
        case .map: return "Karte"
        case .reels: return "Memories"
        case .profileTitle: return "Dein Profil"
        case .saveProfile: return "Änderungen speichern"
        case .saving: return "Speichern…"
        case .resetPassword: return "Passwort zurücksetzen"
        case .viewGlobalLeaderboard: return "Globale Rangliste"
        case .signOut: return "Abmelden"
        case .deleteAccount: return "Mein Konto löschen"
        case .deleteAccountProgress: return "Konto wird gelöscht…"
        case .language: return "Sprache"
        case .reelsTitle: return "Memories"
        case .reelsSubtitle: return "Die Torpilles mit viralem Potenzial."
        case .noReelsTitle: return "Keine veröffentlichten Reels"
        case .noReelsDescription: return "Veröffentliche eine Torpille, wenn du sie der Welt zeigen willst."
        case .savedReelsCommunity: return "Community"
        case .publishToReels: return "Auch in Memories veröffentlichen"
        case .publishedBadge: return "Veröffentlicht"
        case .appLanguage: return "App-Sprache"
        case .authWelcomeTitle: return "Willkommen bei Torpille"
        case .authWelcomeSubtitle: return "Melde dich an oder erstelle dein Konto und starte direkt wieder ins Geschehen."
        case .authSectionTitle: return "Anmeldung"
        case .authSectionSubtitle: return "Gib deine Zugangsdaten ein, um deinen Communitys beizutreten."
        case .authEmailPlaceholder: return "E-Mail"
        case .authPasswordPlaceholder: return "Passwort"
        case .authSignIn: return "Anmelden"
        case .authSignInSubtitle: return "Hol dir dein Konto zurück und kehre in Sekunden zu deinen Runden zurück."
        case .authSignUp: return "Konto erstellen"
        case .authSignUpSubtitle: return "Tippe hier, wenn du noch kein Konto hast."
        case .authForgotPassword: return "Passwort vergessen"
        case .authForgotPasswordSubtitle: return "Erhalte eine E-Mail, um wieder Zugriff auf dein Konto zu bekommen."
        case .authLoading: return "Lädt…"
        case .profileSetupTitle: return "Erstelle dein Profil"
        case .profileSetupSubtitle: return "Füge ein Foto hinzu, wähle einen Nutzernamen und mach deinen Start schon auf dem ersten Bildschirm persönlicher."
        case .profileEmail: return "E-Mail"
        case .profilePseudoPlaceholder: return "Benutzername"
        case .profileContinue: return "Weiter"
        case .profileContinueSubtitle: return "Bestätige dein Profil, um die App zu betreten."
        case .authVerificationNoticeTitle: return "E-Mail-Bestätigung erforderlich"
        case .authVerificationNoticeSubtitle: return "Nach der Registrierung musst du deine E-Mail-Adresse bestätigen, bevor du die App nutzen kannst."
        }
    }

    private func italian(_ key: AppTextKey) -> String {
        switch key {
        case .home: return "Home"
        case .communities: return "Community"
        case .profile: return "Profilo"
        case .leaderboard: return "Classifica"
        case .map: return "Mappa"
        case .reels: return "Memories"
        case .profileTitle: return "Il tuo profilo"
        case .saveProfile: return "Salva modifiche"
        case .saving: return "Salvataggio…"
        case .resetPassword: return "Reimposta password"
        case .viewGlobalLeaderboard: return "Vedi classifica globale"
        case .signOut: return "Disconnetti"
        case .deleteAccount: return "Elimina il mio account"
        case .deleteAccountProgress: return "Eliminazione account…"
        case .language: return "Lingua"
        case .reelsTitle: return "Memories"
        case .reelsSubtitle: return "Le torpilles più pronte a diventare virali."
        case .noReelsTitle: return "Nessun reel pubblicato"
        case .noReelsDescription: return "Pubblica una torpille quando vuoi mostrarla al mondo."
        case .savedReelsCommunity: return "Community"
        case .publishToReels: return "Pubblica anche in Memories"
        case .publishedBadge: return "Pubblicato"
        case .appLanguage: return "Lingua dell'app"
        case .authWelcomeTitle: return "Benvenuto su Torpille"
        case .authWelcomeSubtitle: return "Accedi o crea il tuo account e torna subito nell'azione."
        case .authSectionTitle: return "Accesso"
        case .authSectionSubtitle: return "Inserisci le tue credenziali per entrare nelle tue community."
        case .authEmailPlaceholder: return "Email"
        case .authPasswordPlaceholder: return "Password"
        case .authSignIn: return "Accedi"
        case .authSignInSubtitle: return "Recupera il tuo account e torna alle tue partite in pochi secondi."
        case .authSignUp: return "Crea un account"
        case .authSignUpSubtitle: return "Tocca qui se non hai ancora un account."
        case .authForgotPassword: return "Password dimenticata"
        case .authForgotPasswordSubtitle: return "Ricevi un'email per recuperare l'accesso al tuo account."
        case .authLoading: return "Caricamento…"
        case .profileSetupTitle: return "Crea il tuo profilo"
        case .profileSetupSubtitle: return "Aggiungi una foto, scegli un nome utente e rendi il tuo arrivo più divertente fin dalla prima schermata."
        case .profileEmail: return "Email"
        case .profilePseudoPlaceholder: return "Nome utente"
        case .profileContinue: return "Continua"
        case .profileContinueSubtitle: return "Conferma il tuo profilo per entrare nell'app."
        case .authVerificationNoticeTitle: return "Email da confermare"
        case .authVerificationNoticeSubtitle: return "Dopo la registrazione dovrai confermare il tuo indirizzo email prima di accedere all'app."
        }
    }

    private func portuguese(_ key: AppTextKey) -> String {
        switch key {
        case .home: return "Início"
        case .communities: return "Comunidades"
        case .profile: return "Perfil"
        case .leaderboard: return "Ranking"
        case .map: return "Mapa"
        case .reels: return "Memories"
        case .profileTitle: return "Seu perfil"
        case .saveProfile: return "Salvar alterações"
        case .saving: return "Salvando…"
        case .resetPassword: return "Redefinir senha"
        case .viewGlobalLeaderboard: return "Ver ranking global"
        case .signOut: return "Sair"
        case .deleteAccount: return "Excluir minha conta"
        case .deleteAccountProgress: return "Excluindo conta…"
        case .language: return "Idioma"
        case .reelsTitle: return "Memories"
        case .reelsSubtitle: return "As torpilles com maior potencial viral."
        case .noReelsTitle: return "Nenhum reel publicado"
        case .noReelsDescription: return "Publique uma torpille quando quiser mostrá-la ao mundo."
        case .savedReelsCommunity: return "Comunidade"
        case .publishToReels: return "Publicar também em Memories"
        case .publishedBadge: return "Publicado"
        case .appLanguage: return "Idioma do app"
        case .authWelcomeTitle: return "Bem-vindo ao Torpille"
        case .authWelcomeSubtitle: return "Entre ou crie sua conta e volte direto para a ação."
        case .authSectionTitle: return "Entrar"
        case .authSectionSubtitle: return "Digite suas credenciais para entrar nas suas comunidades."
        case .authEmailPlaceholder: return "Email"
        case .authPasswordPlaceholder: return "Senha"
        case .authSignIn: return "Entrar"
        case .authSignInSubtitle: return "Recupere sua conta e volte para suas partidas em segundos."
        case .authSignUp: return "Criar conta"
        case .authSignUpSubtitle: return "Toque aqui se você ainda não tem uma conta."
        case .authForgotPassword: return "Esqueci minha senha"
        case .authForgotPasswordSubtitle: return "Receba um email para recuperar o acesso à sua conta."
        case .authLoading: return "Carregando…"
        case .profileSetupTitle: return "Crie seu perfil"
        case .profileSetupSubtitle: return "Adicione uma foto, escolha um nome e torne sua chegada mais divertida desde a primeira tela."
        case .profileEmail: return "Email"
        case .profilePseudoPlaceholder: return "Apelido"
        case .profileContinue: return "Continuar"
        case .profileContinueSubtitle: return "Confirme seu perfil para entrar no app."
        case .authVerificationNoticeTitle: return "Email a confirmar"
        case .authVerificationNoticeSubtitle: return "Após o cadastro, você precisará confirmar seu endereço de email antes de entrar no app."
        }
    }
}

enum NotificationMessageKind {
    case text
    case audio
    case image
    case video
    case other
}

struct NotificationMessageDescriptor {
    let sender: String
    let type: NotificationMessageKind
    let snippet: String?
    let taggedPseudo: String?
}
