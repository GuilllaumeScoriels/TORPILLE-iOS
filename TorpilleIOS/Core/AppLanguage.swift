import Foundation
import SwiftUI
import FirebaseFirestore

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
            return "fr"
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
    case authConfirmPasswordPlaceholder
    case authPasswordsMismatch
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
            return .french
        default:
            return language
        }
    }

    var locale: Locale {
        Locale(identifier: effectiveLanguage.localeIdentifier)
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

    func phrase(_ frenchText: String) -> String {
        guard effectiveLanguage != .french && effectiveLanguage != .system else {
            return frenchText
        }

        let catalog = phraseCatalog[effectiveLanguage] ?? [:]
        return catalog[frenchText] ?? frenchText
    }

    /// Localizes status and error strings produced outside SwiftUI. These
    /// messages often contain a pseudo and therefore cannot use an exact
    /// phrase-catalog key.
    func localizedRuntimeMessage(_ message: String) -> String {
        guard effectiveLanguage != .french && effectiveLanguage != .system else { return message }

        let exact: [String: [AppLanguage: String]] = [
            "Profil mis à jour.": [.english: "Profile updated.", .spanish: "Perfil actualizado.", .german: "Profil aktualisiert.", .italian: "Profilo aggiornato.", .portuguese: "Perfil atualizado."],
            "Préférences publiques enregistrées.": [.english: "Public preferences saved.", .spanish: "Preferencias públicas guardadas.", .german: "Öffentliche Einstellungen gespeichert.", .italian: "Preferenze pubbliche salvate.", .portuguese: "Preferências públicas salvas."],
            "Communauté retirée de l’accueil.": [.english: "Community removed from Home.", .spanish: "Comunidad eliminada del inicio.", .german: "Community von der Startseite entfernt.", .italian: "Community rimossa dalla schermata Home.", .portuguese: "Comunidade removida do início."],
            "Communauté épinglée dans l’accueil.": [.english: "Community pinned to Home.", .spanish: "Comunidad fijada en el inicio.", .german: "Community auf der Startseite angeheftet.", .italian: "Community fissata nella schermata Home.", .portuguese: "Comunidade fixada no início."],
            "Tu peux épingler jusqu’à 3 communautés.": [.english: "You can pin up to 3 communities.", .spanish: "Puedes fijar hasta 3 comunidades.", .german: "Du kannst bis zu 3 Communitys anheften.", .italian: "Puoi fissare fino a 3 community.", .portuguese: "Você pode fixar até 3 comunidades."],
            "Ta demande a été envoyée à l'administrateur. Tu recevras une notification après sa décision.": [.english: "Your request was sent to the administrator. You will receive a notification after their decision.", .spanish: "Tu solicitud se envió al administrador. Recibirás una notificación después de su decisión.", .german: "Deine Anfrage wurde an den Administrator gesendet. Nach der Entscheidung erhältst du eine Benachrichtigung.", .italian: "La tua richiesta è stata inviata all'amministratore. Riceverai una notifica dopo la decisione.", .portuguese: "Sua solicitação foi enviada ao administrador. Você receberá uma notificação após a decisão."],
            "Parametres enregistres.": [.english: "Settings saved.", .spanish: "Ajustes guardados.", .german: "Einstellungen gespeichert.", .italian: "Impostazioni salvate.", .portuguese: "Configurações salvas."],
            "Signalement envoyé. Une confirmation te sera transmise.": [.english: "Report sent. You will receive a confirmation.", .spanish: "Reporte enviado. Recibirás una confirmación.", .german: "Meldung gesendet. Du erhältst eine Bestätigung.", .italian: "Segnalazione inviata. Riceverai una conferma.", .portuguese: "Denúncia enviada. Você receberá uma confirmação."],
            "Signalement envoyé. Notre équipe vérifie la situation.": [.english: "Report sent. Our team is reviewing the situation.", .spanish: "Reporte enviado. Nuestro equipo está revisando la situación.", .german: "Meldung gesendet. Unser Team prüft die Situation.", .italian: "Segnalazione inviata. Il nostro team sta verificando la situazione.", .portuguese: "Denúncia enviada. Nossa equipe está analisando a situação."],
            "Signalement envoyé. Notre équipe vérifie ce contenu.": [.english: "Report sent. Our team is reviewing this content.", .spanish: "Reporte enviado. Nuestro equipo está revisando este contenido.", .german: "Meldung gesendet. Unser Team prüft diesen Inhalt.", .italian: "Segnalazione inviata. Il nostro team sta verificando questo contenuto.", .portuguese: "Denúncia enviada. Nossa equipe está analisando este conteúdo."],
            "Ce contenu est deja enregistre.": [.english: "This content is already saved.", .spanish: "Este contenido ya está guardado.", .german: "Dieser Inhalt ist bereits gespeichert.", .italian: "Questo contenuto è già salvato.", .portuguese: "Este conteúdo já está salvo."],
            "Impossible d'enregistrer ce contenu.": [.english: "This content could not be saved.", .spanish: "No se pudo guardar este contenido.", .german: "Dieser Inhalt konnte nicht gespeichert werden.", .italian: "Impossibile salvare questo contenuto.", .portuguese: "Não foi possível salvar este conteúdo."],
            "Contenu enregistre dans la discussion.": [.english: "Content saved in the conversation.", .spanish: "Contenido guardado en la conversación.", .german: "Inhalt in der Unterhaltung gespeichert.", .italian: "Contenuto salvato nella conversazione.", .portuguese: "Conteúdo salvo na conversa."],
            "La torpille a ete publiee dans Memories.": [.english: "The torpille was published to Memories.", .spanish: "La torpille se publicó en Memories.", .german: "Die Torpille wurde in Memories veröffentlicht.", .italian: "La torpille è stata pubblicata in Memories.", .portuguese: "A torpille foi publicada em Memories."],
            "La torpille a ete retiree des Memories.": [.english: "The torpille was removed from Memories.", .spanish: "La torpille se eliminó de Memories.", .german: "Die Torpille wurde aus Memories entfernt.", .italian: "La torpille è stata rimossa da Memories.", .portuguese: "A torpille foi removida de Memories."],
            "Renseigne ton mot de passe.": [.english: "Enter your password.", .spanish: "Introduce tu contraseña.", .german: "Gib dein Passwort ein.", .italian: "Inserisci la password.", .portuguese: "Digite sua senha."],
            "Choisis un mot de passe d'au moins 6 caractères.": [.english: "Choose a password of at least 6 characters.", .spanish: "Elige una contraseña de al menos 6 caracteres.", .german: "Wähle ein Passwort mit mindestens 6 Zeichen.", .italian: "Scegli una password di almeno 6 caratteri.", .portuguese: "Escolha uma senha com pelo menos 6 caracteres."],
            "Adresse email invalide. Vérifie le format, par exemple nom@example.com.": [.english: "Invalid email address. Check the format, for example name@example.com.", .spanish: "Dirección de correo no válida. Comprueba el formato, por ejemplo nombre@example.com.", .german: "Ungültige E-Mail-Adresse. Prüfe das Format, zum Beispiel name@example.com.", .italian: "Indirizzo email non valido. Controlla il formato, ad esempio nome@example.com.", .portuguese: "Endereço de email inválido. Verifique o formato, por exemplo nome@example.com."],
            "Choisis un membre de la communauté avant d'envoyer la torpille.": [.english: "Choose a community member before sending the torpille.", .spanish: "Elige un miembro de la comunidad antes de enviar la torpille.", .german: "Wähle vor dem Senden der Torpille ein Community-Mitglied aus.", .italian: "Scegli un membro della community prima di inviare la torpille.", .portuguese: "Escolha um membro da comunidade antes de enviar a torpille."],
            "Complète obligatoirement ton prénom, ton nom et ton pseudo, puis accepte les règles EULA et la politique de confidentialité avant de continuer.": [.english: "Enter your first name, last name and username, then accept the EULA rules and privacy policy before continuing.", .spanish: "Introduce tu nombre, apellido y apodo, y acepta las reglas EULA y la política de privacidad antes de continuar.", .german: "Gib deinen Vor- und Nachnamen sowie deinen Benutzernamen ein und akzeptiere anschließend die EULA-Regeln und die Datenschutzerklärung, bevor du fortfährst.", .italian: "Inserisci nome, cognome e nome utente, quindi accetta le regole EULA e l’informativa sulla privacy prima di continuare.", .portuguese: "Informe seu nome, sobrenome e nome de usuário e aceite as regras EULA e a política de privacidade antes de continuar."],
            "Complète obligatoirement ton prénom, ton nom et ton pseudo, puis accepte les règles EULA et la politique de confidentialité avant de créer une communauté.": [.english: "Enter your first name, last name and username, then accept the EULA rules and privacy policy before creating a community.", .spanish: "Introduce tu nombre, apellido y apodo, y acepta las reglas EULA y la política de privacidad antes de crear una comunidad.", .german: "Gib deinen Vor- und Nachnamen sowie deinen Benutzernamen ein und akzeptiere die EULA-Regeln und die Datenschutzerklärung, bevor du eine Community erstellst.", .italian: "Inserisci nome, cognome e nome utente, quindi accetta le regole EULA e l’informativa sulla privacy prima di creare una community.", .portuguese: "Informe seu nome, sobrenome e nome de usuário e aceite as regras EULA e a política de privacidade antes de criar uma comunidade."],
            "Le profil a été enregistré mais reste incomplet.": [.english: "The profile was saved but is still incomplete. Complete all required fields and accept the EULA.", .spanish: "El perfil se guardó, pero sigue incompleto. Completa todos los campos obligatorios y acepta el EULA.", .german: "Das Profil wurde gespeichert, ist aber noch unvollständig. Fülle alle Pflichtfelder aus und akzeptiere die EULA.", .italian: "Il profilo è stato salvato ma è ancora incompleto. Compila tutti i campi obbligatori e accetta l’EULA.", .portuguese: "O perfil foi salvo, mas ainda está incompleto. Preencha todos os campos obrigatórios e aceite o EULA."],
            "Ton profil n’est pas encore configuré. Complète les informations obligatoires et accepte l’EULA pour continuer.": [.english: "Your profile is not configured yet. Complete the required information and accept the EULA to continue.", .spanish: "Tu perfil aún no está configurado. Completa la información obligatoria y acepta el EULA para continuar.", .german: "Dein Profil ist noch nicht eingerichtet. Vervollständige die Pflichtangaben und akzeptiere die EULA, um fortzufahren.", .italian: "Il tuo profilo non è ancora configurato. Completa le informazioni obbligatorie e accetta l’EULA per continuare.", .portuguese: "Seu perfil ainda não está configurado. Preencha as informações obrigatórias e aceite o EULA para continuar."],
            "L'enregistrement du profil est refusé par Firestore. Déploie les règles Firestore à jour puis réessaie.": [.english: "Firestore rejected the profile save. Deploy the latest Firestore rules and try again.", .spanish: "Firestore rechazó el guardado del perfil. Implementa las reglas de Firestore actualizadas y vuelve a intentarlo.", .german: "Firestore hat das Speichern des Profils abgelehnt. Stelle die aktuellen Firestore-Regeln bereit und versuche es erneut.", .italian: "Firestore ha rifiutato il salvataggio del profilo. Distribuisci le regole Firestore aggiornate e riprova.", .portuguese: "O Firestore recusou o salvamento do perfil. Implante as regras atualizadas do Firestore e tente novamente."],
            "Ce pseudo est déjà utilisé par un autre utilisateur. Choisis un autre pseudo pour continuer.": [.english: "This username is already used by another user. Choose another username to continue.", .spanish: "Este nombre de usuario ya lo utiliza otro usuario. Elige otro para continuar.", .german: "Dieser Benutzername wird bereits von einer anderen Person verwendet. Wähle einen anderen, um fortzufahren.", .italian: "Questo nome utente è già utilizzato da un altro utente. Scegline un altro per continuare.", .portuguese: "Este nome de usuário já está sendo usado por outra pessoa. Escolha outro para continuar."]
        ]
        if let translated = exact[message]?[effectiveLanguage] { return translated }
        let catalogTranslation = phrase(message)
        if catalogTranslation != message { return catalogTranslation }

        let patterns: [(String, String, [AppLanguage: (String, String)])] = [
            ("Demande d'ami envoyée à @", ".", [.english: ("Friend request sent to @", "."), .spanish: ("Solicitud de amistad enviada a @", "."), .german: ("Freundschaftsanfrage an @", " gesendet."), .italian: ("Richiesta di amicizia inviata a @", "."), .portuguese: ("Solicitação de amizade enviada para @", ".")]),
            ("@", " a été retiré de tes amis.", [.english: ("@", " was removed from your friends."), .spanish: ("@", " fue eliminado de tus amigos."), .german: ("@", " wurde aus deinen Freunden entfernt."), .italian: ("@", " è stato rimosso dai tuoi amici."), .portuguese: ("@", " foi removido dos seus amigos.")]),
            ("@", " a été débloqué.", [.english: ("@", " was unblocked."), .spanish: ("@", " fue desbloqueado."), .german: ("@", " wurde entsperrt."), .italian: ("@", " è stato sbloccato."), .portuguese: ("@", " foi desbloqueado.")]),
            ("@", " a rejoint la communauté.", [.english: ("@", " joined the community."), .spanish: ("@", " se unió a la comunidad."), .german: ("@", " ist der Community beigetreten."), .italian: ("@", " è entrato nella community."), .portuguese: ("@", " entrou na comunidade.")]),
            ("La demande de @", " a été refusée.", [.english: ("@", "'s request was declined."), .spanish: ("La solicitud de @", " fue rechazada."), .german: ("Die Anfrage von @", " wurde abgelehnt."), .italian: ("La richiesta di @", " è stata rifiutata."), .portuguese: ("A solicitação de @", " foi recusada.")]),
            ("@", " a ete retire de la communaute.", [.english: ("@", " was removed from the community."), .spanish: ("@", " fue eliminado de la comunidad."), .german: ("@", " wurde aus der Community entfernt."), .italian: ("@", " è stato rimosso dalla community."), .portuguese: ("@", " foi removido da comunidade.")]),
            ("@", " a ete banni.", [.english: ("@", " was banned."), .spanish: ("@", " fue expulsado."), .german: ("@", " wurde gesperrt."), .italian: ("@", " è stato espulso."), .portuguese: ("@", " foi banido.")]),
            ("Les contenus de @", " sont masqués dans cette communauté.", [.english: ("Content from @", " is hidden in this community."), .spanish: ("El contenido de @", " está oculto en esta comunidad."), .german: ("Inhalte von @", " sind in dieser Community ausgeblendet."), .italian: ("I contenuti di @", " sono nascosti in questa community."), .portuguese: ("O conteúdo de @", " está oculto nesta comunidade.")]),
            ("Les contenus de @", " sont réaffichés dans cette communauté.", [.english: ("Content from @", " is visible again in this community."), .spanish: ("El contenido de @", " vuelve a mostrarse en esta comunidad."), .german: ("Inhalte von @", " werden in dieser Community wieder angezeigt."), .italian: ("I contenuti di @", " sono nuovamente visibili in questa community."), .portuguese: ("O conteúdo de @", " está visível novamente nesta comunidade.")]),
            ("@", " a été bloqué.", [.english: ("@", " was blocked."), .spanish: ("@", " fue bloqueado."), .german: ("@", " wurde blockiert."), .italian: ("@", " è stato bloccato."), .portuguese: ("@", " foi bloqueado.")]),
            ("@", " a été bloqué. Ses contenus sont désormais masqués.", [.english: ("@", " was blocked. Their content is now hidden."), .spanish: ("@", " fue bloqueado. Su contenido ahora está oculto."), .german: ("@", " wurde blockiert. Die Inhalte sind jetzt ausgeblendet."), .italian: ("@", " è stato bloccato. I suoi contenuti ora sono nascosti."), .portuguese: ("@", " foi bloqueado. O conteúdo agora está oculto.")])
        ]
        for (prefix, suffix, translations) in patterns where message.hasPrefix(prefix) && message.hasSuffix(suffix) {
            let start = message.index(message.startIndex, offsetBy: prefix.count)
            let end = message.index(message.endIndex, offsetBy: -suffix.count)
            guard start <= end, let translated = translations[effectiveLanguage] else { continue }
            return translated.0 + String(message[start..<end]) + translated.1
        }

        switch effectiveLanguage {
        case .english: return "The operation could not be completed. Please try again."
        case .spanish: return "No se pudo completar la operación. Inténtalo de nuevo."
        case .german: return "Der Vorgang konnte nicht abgeschlossen werden. Bitte versuche es erneut."
        case .italian: return "Impossibile completare l'operazione. Riprova."
        case .portuguese: return "Não foi possível concluir a operação. Tente novamente."
        case .system, .french: return message
        }
    }

    func requiredProfileAlertTitle() -> String {
        switch effectiveLanguage {
        case .system, .french: return "Profil obligatoire"
        case .english: return "Profile required"
        case .spanish: return "Perfil obligatorio"
        case .german: return "Profil erforderlich"
        case .italian: return "Profilo obbligatorio"
        case .portuguese: return "Perfil obrigatório"
        }
    }

    func localizedFriendRequestConfirmation(pseudo: String) -> String {
        switch effectiveLanguage {
        case .system, .french: return "@\(pseudo) recevra une demande d'ami qu'il devra accepter."
        case .english: return "@\(pseudo) will receive a friend request that they must accept."
        case .spanish: return "@\(pseudo) recibirá una solicitud de amistad que deberá aceptar."
        case .german: return "@\(pseudo) erhält eine Freundschaftsanfrage, die angenommen werden muss."
        case .italian: return "@\(pseudo) riceverà una richiesta di amicizia che dovrà accettare."
        case .portuguese: return "@\(pseudo) receberá uma solicitação de amizade que deverá aceitar."
        }
    }

    func localizedFriendRemovalConfirmation(pseudo: String) -> String {
        switch effectiveLanguage {
        case .system, .french: return "L'amitié avec @\(pseudo) sera supprimée pour vous deux. Cette personne en sera informée."
        case .english: return "Your friendship with @\(pseudo) will be removed for both of you. This person will be notified."
        case .spanish: return "La amistad con @\(pseudo) se eliminará para ambos. Esta persona será informada."
        case .german: return "Die Freundschaft mit @\(pseudo) wird für euch beide entfernt. Diese Person wird benachrichtigt."
        case .italian: return "L'amicizia con @\(pseudo) verrà rimossa per entrambi. Questa persona sarà informata."
        case .portuguese: return "A amizade com @\(pseudo) será removida para ambos. Essa pessoa será informada."
        }
    }

    func xpTotalLabel(_ xpTotal: Int64) -> String {
        switch effectiveLanguage {
        case .system, .french:
            return "XP total : \(xpTotal)"
        case .english:
            return "Total XP: \(xpTotal)"
        case .spanish:
            return "XP total: \(xpTotal)"
        case .german:
            return "XP gesamt: \(xpTotal)"
        case .italian:
            return "XP totali: \(xpTotal)"
        case .portuguese:
            return "XP total: \(xpTotal)"
        }
    }

    func friendCountLabel(_ count: Int) -> String {
        switch effectiveLanguage {
        case .system, .french:
            return "\(count) ami\(count > 1 ? "s" : "")"
        case .english:
            return count == 1 ? "1 friend" : "\(count) friends"
        case .spanish:
            return count == 1 ? "1 amigo" : "\(count) amigos"
        case .german:
            return count == 1 ? "1 Freund" : "\(count) Freunde"
        case .italian:
            return count == 1 ? "1 amico" : "\(count) amici"
        case .portuguese:
            return count == 1 ? "1 amigo" : "\(count) amigos"
        }
    }

    func friendCountWord(_ count: Int) -> String {
        friendCountLabel(count).replacingOccurrences(of: "\(count) ", with: "")
    }

    func visibleTorpilleursLabel(_ count: Int) -> String {
        switch effectiveLanguage {
        case .system, .french:
            return "\(count) torpilleur(s) affiché(s)"
        case .english:
            return count == 1 ? "1 torpilleur shown" : "\(count) torpilleurs shown"
        case .spanish:
            return count == 1 ? "1 torpilleur visible" : "\(count) torpilleurs visibles"
        case .german:
            return count == 1 ? "1 Torpilleur angezeigt" : "\(count) Torpilleurs angezeigt"
        case .italian:
            return count == 1 ? "1 torpilleur mostrato" : "\(count) torpilleurs mostrati"
        case .portuguese:
            return count == 1 ? "1 torpilleur exibido" : "\(count) torpilleurs exibidos"
        }
    }

    func mapMemberSubtitle(lastTorpilledAt: Timestamp?, locationUpdatedAt: Timestamp?) -> String {
        let torpilleDate = lastTorpilledAt?.formattedDateTime ?? "—"
        let locationDate = locationUpdatedAt?.formattedDateTime ?? "—"
        switch effectiveLanguage {
        case .system, .french: return "Dernière torpille : \(torpilleDate) • Position mise à jour : \(locationDate)"
        case .english: return "Latest torpille: \(torpilleDate) • Location updated: \(locationDate)"
        case .spanish: return "Última torpille: \(torpilleDate) • Ubicación actualizada: \(locationDate)"
        case .german: return "Letzte Torpille: \(torpilleDate) • Standort aktualisiert: \(locationDate)"
        case .italian: return "Ultima torpille: \(torpilleDate) • Posizione aggiornata: \(locationDate)"
        case .portuguese: return "Última torpille: \(torpilleDate) • Localização atualizada: \(locationDate)"
        }
    }

    var myCurrentLocationLabel: String {
        switch effectiveLanguage {
        case .system, .french: return "Ma position actuelle"
        case .english: return "My current location"
        case .spanish: return "Mi ubicación actual"
        case .german: return "Mein aktueller Standort"
        case .italian: return "La mia posizione attuale"
        case .portuguese: return "Minha localização atual"
        }
    }

    func sendInCommunityLabel(_ communityName: String) -> String {
        switch effectiveLanguage {
        case .system, .french:
            return "Envoyer dans \(communityName)"
        case .english:
            return "Send in \(communityName)"
        case .spanish:
            return "Enviar en \(communityName)"
        case .german:
            return "In \(communityName) senden"
        case .italian:
            return "Invia in \(communityName)"
        case .portuguese:
            return "Enviar em \(communityName)"
        }
    }

    func noSharedCommunityLabel(_ pseudo: String) -> String {
        switch effectiveLanguage {
        case .system, .french:
            return "Aucune communauté partagée avec @\(pseudo)."
        case .english:
            return "No shared community with @\(pseudo)."
        case .spanish:
            return "No hay comunidad compartida con @\(pseudo)."
        case .german:
            return "Keine gemeinsame Community mit @\(pseudo)."
        case .italian:
            return "Nessuna community condivisa con @\(pseudo)."
        case .portuguese:
            return "Nenhuma comunidade compartilhada com @\(pseudo)."
        }
    }

    func torpilleUserLabel(_ pseudo: String) -> String {
        switch effectiveLanguage {
        case .system, .french:
            return "Torpiller @\(pseudo)"
        case .english:
            return "Torpille @\(pseudo)"
        case .spanish:
            return "Torpillear a @\(pseudo)"
        case .german:
            return "@\(pseudo) torpillieren"
        case .italian:
            return "Torpilla @\(pseudo)"
        case .portuguese:
            return "Torpillar @\(pseudo)"
        }
    }

    func chooseWhereToTorpilleLabel(_ pseudo: String) -> String {
        switch effectiveLanguage {
        case .system, .french:
            return "Choisir où torpiller @\(pseudo)"
        case .english:
            return "Choose where to torpille @\(pseudo)"
        case .spanish:
            return "Elegir dónde torpillear a @\(pseudo)"
        case .german:
            return "Auswählen, wo @\(pseudo) torpilliert wird"
        case .italian:
            return "Scegli dove torpillare @\(pseudo)"
        case .portuguese:
            return "Escolher onde torpillar @\(pseudo)"
        }
    }

    func hoursLabel(_ value: Int) -> String {
        switch effectiveLanguage {
        case .system, .french:
            return value == 1 ? "1 heure" : "\(value) heures"
        case .english:
            return value == 1 ? "1 hour" : "\(value) hours"
        case .spanish:
            return value == 1 ? "1 hora" : "\(value) horas"
        case .german:
            return value == 1 ? "1 Stunde" : "\(value) Stunden"
        case .italian:
            return value == 1 ? "1 ora" : "\(value) ore"
        case .portuguese:
            return value == 1 ? "1 hora" : "\(value) horas"
        }
    }

    func minutesLabel(_ value: Int) -> String {
        switch effectiveLanguage {
        case .system, .french:
            return value == 1 ? "1 minute" : "\(value) minutes"
        case .english:
            return value == 1 ? "1 minute" : "\(value) minutes"
        case .spanish:
            return value == 1 ? "1 minuto" : "\(value) minutos"
        case .german:
            return value == 1 ? "1 Minute" : "\(value) Minuten"
        case .italian:
            return value == 1 ? "1 minuto" : "\(value) minuti"
        case .portuguese:
            return value == 1 ? "1 minuto" : "\(value) minutos"
        }
    }

    func currentDelayLabel(_ duration: String) -> String {
        switch effectiveLanguage {
        case .system, .french:
            return "Délai actuel : \(duration)"
        case .english:
            return "Current delay: \(duration)"
        case .spanish:
            return "Plazo actual: \(duration)"
        case .german:
            return "Aktuelle Frist: \(duration)"
        case .italian:
            return "Tempo attuale: \(duration)"
        case .portuguese:
            return "Prazo atual: \(duration)"
        }
    }

    func invitationLinkLabel(_ url: String) -> String {
        switch effectiveLanguage {
        case .system, .french:
            return "Invitation : \(url)"
        case .english:
            return "Invitation: \(url)"
        case .spanish:
            return "Invitación: \(url)"
        case .german:
            return "Einladung: \(url)"
        case .italian:
            return "Invito: \(url)"
        case .portuguese:
            return "Convite: \(url)"
        }
    }

    var copyInvitationLinkLabel: String {
        switch effectiveLanguage {
        case .system, .french: return "Copier le lien"
        case .english: return "Copy link"
        case .spanish: return "Copiar enlace"
        case .german: return "Link kopieren"
        case .italian: return "Copia link"
        case .portuguese: return "Copiar link"
        }
    }

    func communityJoinRequestBody(communityName: String) -> String {
        switch effectiveLanguage {
        case .system, .french: return "souhaite rejoindre \(communityName)."
        case .english: return "wants to join \(communityName)."
        case .spanish: return "quiere unirse a \(communityName)."
        case .german: return "möchte \(communityName) beitreten."
        case .italian: return "vuole unirsi a \(communityName)."
        case .portuguese: return "quer entrar em \(communityName)."
        }
    }

    var mediaSendConfirmationTitle: String {
        switch effectiveLanguage {
        case .system, .french: return "Envoyer ce média ?"
        case .english: return "Send this media?"
        case .spanish: return "¿Enviar este contenido?"
        case .german: return "Dieses Medium senden?"
        case .italian: return "Inviare questo contenuto?"
        case .portuguese: return "Enviar esta mídia?"
        }
    }

    var mediaSendConfirmationMessage: String {
        switch effectiveLanguage {
        case .system, .french: return "Le média ne sera envoyé qu’après ta confirmation."
        case .english: return "The media will only be sent after you confirm."
        case .spanish: return "El contenido solo se enviará después de tu confirmación."
        case .german: return "Das Medium wird erst nach deiner Bestätigung gesendet."
        case .italian: return "Il contenuto verrà inviato solo dopo la tua conferma."
        case .portuguese: return "A mídia só será enviada após sua confirmação."
        }
    }

    func communityJoinDecisionTitle(accepted: Bool) -> String {
        switch effectiveLanguage {
        case .system, .french: return accepted ? "Demande acceptée" : "Demande refusée"
        case .english: return accepted ? "Request accepted" : "Request declined"
        case .spanish: return accepted ? "Solicitud aceptada" : "Solicitud rechazada"
        case .german: return accepted ? "Anfrage angenommen" : "Anfrage abgelehnt"
        case .italian: return accepted ? "Richiesta accettata" : "Richiesta rifiutata"
        case .portuguese: return accepted ? "Solicitação aceita" : "Solicitação recusada"
        }
    }

    func communityJoinDecisionBody(communityName: String, accepted: Bool) -> String {
        switch effectiveLanguage {
        case .system, .french:
            return accepted ? "Tu peux maintenant accéder à \(communityName)." : "Ta demande pour rejoindre \(communityName) a été refusée."
        case .english:
            return accepted ? "You can now access \(communityName)." : "Your request to join \(communityName) was declined."
        case .spanish:
            return accepted ? "Ahora puedes acceder a \(communityName)." : "Tu solicitud para unirte a \(communityName) fue rechazada."
        case .german:
            return accepted ? "Du kannst jetzt auf \(communityName) zugreifen." : "Deine Anfrage für \(communityName) wurde abgelehnt."
        case .italian:
            return accepted ? "Ora puoi accedere a \(communityName)." : "La tua richiesta di entrare in \(communityName) è stata rifiutata."
        case .portuguese:
            return accepted ? "Agora você pode acessar \(communityName)." : "Sua solicitação para entrar em \(communityName) foi recusada."
        }
    }

    func xpInCommunityLabel(_ xp: Int64) -> String {
        switch effectiveLanguage {
        case .system, .french:
            return "XP : \(xp)"
        case .english:
            return "XP: \(xp)"
        case .spanish:
            return "XP: \(xp)"
        case .german:
            return "XP: \(xp)"
        case .italian:
            return "XP: \(xp)"
        case .portuguese:
            return "XP: \(xp)"
        }
    }

    func actionsForMemberLabel(_ displayName: String) -> String {
        switch effectiveLanguage {
        case .system, .french:
            return "Actions pour \(displayName)"
        case .english:
            return "Actions for \(displayName)"
        case .spanish:
            return "Acciones para \(displayName)"
        case .german:
            return "Aktionen für \(displayName)"
        case .italian:
            return "Azioni per \(displayName)"
        case .portuguese:
            return "Ações para \(displayName)"
        }
    }

    func savedAtLabel(_ dateText: String) -> String {
        switch effectiveLanguage {
        case .system, .french:
            return "Enregistre le \(dateText)"
        case .english:
            return "Saved on \(dateText)"
        case .spanish:
            return "Guardado el \(dateText)"
        case .german:
            return "Gespeichert am \(dateText)"
        case .italian:
            return "Salvato il \(dateText)"
        case .portuguese:
            return "Salvo em \(dateText)"
        }
    }

    func videoForUserLabel(_ pseudo: String) -> String {
        switch effectiveLanguage {
        case .system, .french:
            return "Video pour @\(pseudo)"
        case .english:
            return "Video for @\(pseudo)"
        case .spanish:
            return "Vídeo para @\(pseudo)"
        case .german:
            return "Video für @\(pseudo)"
        case .italian:
            return "Video per @\(pseudo)"
        case .portuguese:
            return "Vídeo para @\(pseudo)"
        }
    }

    func selectedCommunityLabel(_ communityName: String) -> String {
        switch effectiveLanguage {
        case .system, .french:
            return "\(communityName) sélectionnée"
        case .english:
            return "\(communityName) selected"
        case .spanish:
            return "\(communityName) seleccionada"
        case .german:
            return "\(communityName) ausgewählt"
        case .italian:
            return "\(communityName) selezionata"
        case .portuguese:
            return "\(communityName) selecionada"
        }
    }

    func voiceFromLabel(_ pseudo: String) -> String {
        switch effectiveLanguage {
        case .system, .french:
            return "Vocal de \(pseudo)"
        case .english:
            return "Voice message from \(pseudo)"
        case .spanish:
            return "Voz de \(pseudo)"
        case .german:
            return "Sprachnachricht von \(pseudo)"
        case .italian:
            return "Vocale di \(pseudo)"
        case .portuguese:
            return "Áudio de \(pseudo)"
        }
    }

    func iconAccessibilityLabel(_ icon: String) -> String {
        switch effectiveLanguage {
        case .system, .french:
            return "Icône \(icon)"
        case .english:
            return "Icon \(icon)"
        case .spanish:
            return "Icono \(icon)"
        case .german:
            return "Symbol \(icon)"
        case .italian:
            return "Icona \(icon)"
        case .portuguese:
            return "Ícone \(icon)"
        }
    }

    func toWatchLabel(_ count: Int) -> String {
        switch effectiveLanguage {
        case .system, .french:
            return "\(count) à regarder"
        case .english:
            return count == 1 ? "1 to watch" : "\(count) to watch"
        case .spanish:
            return count == 1 ? "1 por ver" : "\(count) por ver"
        case .german:
            return count == 1 ? "1 zum Ansehen" : "\(count) zum Ansehen"
        case .italian:
            return count == 1 ? "1 da guardare" : "\(count) da guardare"
        case .portuguese:
            return count == 1 ? "1 para assistir" : "\(count) para assistir"
        }
    }

    func replyToTorpilleLabel(_ pseudo: String) -> String {
        switch effectiveLanguage {
        case .system, .french:
            return "Réponds à la torpille de @\(pseudo)!"
        case .english:
            return "Reply to @\(pseudo)'s torpille!"
        case .spanish:
            return "¡Responde a la torpille de @\(pseudo)!"
        case .german:
            return "Antworte auf die Torpille von @\(pseudo)!"
        case .italian:
            return "Rispondi alla torpille di @\(pseudo)!"
        case .portuguese:
            return "Responda à torpille de @\(pseudo)!"
        }
    }

    func readyVideoLabel(_ filename: String) -> String {
        switch effectiveLanguage {
        case .system, .french:
            return "Vidéo prête : \(filename)"
        case .english:
            return "Video ready: \(filename)"
        case .spanish:
            return "Vídeo listo: \(filename)"
        case .german:
            return "Video bereit: \(filename)"
        case .italian:
            return "Video pronto: \(filename)"
        case .portuguese:
            return "Vídeo pronto: \(filename)"
        }
    }

    func confirmTorpilleRecipientLabel(_ pseudo: String) -> String {
        switch effectiveLanguage {
        case .system, .french:
            return "Envoyer cette torpille à @\(pseudo) ?"
        case .english:
            return "Send this torpille to @\(pseudo)?"
        case .spanish:
            return "¿Enviar esta torpille a @\(pseudo)?"
        case .german:
            return "Diese Torpille an @\(pseudo) senden?"
        case .italian:
            return "Inviare questa torpille a @\(pseudo)?"
        case .portuguese:
            return "Enviar esta torpille para @\(pseudo)?"
        }
    }

    func acceptAndSendToLabel(_ pseudo: String) -> String {
        switch effectiveLanguage {
        case .system, .french:
            return "Accepter et envoyer à @\(pseudo)"
        case .english:
            return "Accept and send to @\(pseudo)"
        case .spanish:
            return "Aceptar y enviar a @\(pseudo)"
        case .german:
            return "Akzeptieren und an @\(pseudo) senden"
        case .italian:
            return "Accetta e invia a @\(pseudo)"
        case .portuguese:
            return "Aceitar e enviar para @\(pseudo)"
        }
    }

    func torpilleArrowLabel(_ pseudo: String) -> String {
        switch effectiveLanguage {
        case .system, .french:
            return "Torpille → @\(pseudo)"
        case .english:
            return "Torpille → @\(pseudo)"
        case .spanish:
            return "Torpille → @\(pseudo)"
        case .german:
            return "Torpille → @\(pseudo)"
        case .italian:
            return "Torpille → @\(pseudo)"
        case .portuguese:
            return "Torpille → @\(pseudo)"
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

    func torpilleActionNotificationBody(from sender: String, to target: String) -> String {
        let resolvedSender = sender.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? localizedSomeone() : sender
        let resolvedTarget = target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? localizedSomeone() : target
        return "\(resolvedSender) a torpillé \(resolvedTarget)"
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

    private var phraseCatalog: [AppLanguage: [String: String]] {
        [
            .english: [
                "Sexe": "Sex",
                "Homme": "Male",
                "Femme": "Female",
                "Non binaire": "Non-binary",
                "Non renseigné": "Not specified",
                "Ton adresse email est déjà vérifiée. Tu peux te connecter.": "Your email address is already verified. You can sign in.",
                "Trop de tentatives. Patiente quelques instants avant de renvoyer un email.": "Too many attempts. Wait a while before resending an email.",
                "Continuer": "Continue",
                "Avant de rejoindre Torpille": "Before joining Torpille",
                "Lis et accepte les règles EULA et la politique de confidentialité pour accéder à la connexion ou à la création de compte.": "Read and accept the EULA rules and privacy policy to sign in or create an account.",
                "J’accepte les règles EULA": "I accept the EULA rules",
                "Lire la politique de confidentialité": "Read the privacy policy",
                "J’accepte la politique de confidentialité": "I accept the privacy policy",
                "Les deux acceptations sont obligatoires pour continuer.": "Both agreements are required to continue.",
                "Revoir mes acceptations": "Review my agreements",
                "Lu et accepté": "Read and accepted",
                "Lis et accepte les règles EULA et la politique de confidentialité avant de continuer.": "Read and accept the EULA rules and privacy policy before continuing.",
                "Conditions obligatoires avant connexion ou inscription": "Required terms before signing in or registering",
                "Tu dois ouvrir puis accepter les deux documents sur cet appareil avant de continuer.": "You must open and accept both documents on this device before continuing.",
                "Accepté sur cet appareil": "Accepted on this device",
                "Ouvrir et accepter": "Open and accept",
                "Lis et accepte l’EULA et les règles de l’app avant de te connecter.": "Read and accept the EULA and app rules before signing in.",
                "Lis et accepte l’EULA et les règles de l’app avant de créer un compte.": "Read and accept the EULA and app rules before creating an account.",
                "Chargement…": "Loading...",
                "Retour": "Back",
                "Fermer": "Close",
                "Annuler": "Cancel",
                "Supprimer": "Delete",
                "Envoyer": "Send",
                "Créer": "Create",
                "Création…": "Creating...",
                "Galerie": "Gallery",
                "Accueil": "Home",
                "Communautés": "Communities",
                "Profil": "Profile",
                "Activité": "Activity",
                "Réglages": "Settings",
                "Préférences": "Preferences",
                "Préférences par communauté": "Preferences by community",
                "Choisir quand chaque communauté peut te notifier.": "Choose when each community can notify you.",
                "Activité et demandes": "Activity and requests",
                "Aucune notification": "No notifications",
                "Les nouvelles notifications reçues apparaîtront ici.": "New notifications will appear here.",
                "Tout lu": "Mark all read",
                "Les notifications sont automatiquement supprimées après deux semaines.": "Notifications are automatically deleted after two weeks.",
                "Refuser": "Decline",
                "Accepter": "Accept",
                "veut devenir ami avec toi.": "wants to become friends with you.",
                "Notifications": "Notifications",
                "Aucune communauté": "No community",
                "Rejoins ou crée une communauté pour configurer tes notifications.": "Join or create a community to configure your notifications.",
                "Choisis si chaque communauté doit te notifier pour tous les contenus ou seulement quand tu es identifié·e.": "Choose whether each community notifies you for all content or only when you are tagged.",
                "Créer une communauté": "Create a community",
                "Classement global": "Global leaderboard",
                "Dernière communauté": "Latest community",
                "Communautés épinglées": "Pinned communities",
                "Actions rapides": "Quick actions",
                "Aucune communauté pour le moment.": "No community yet.",
                "Crée ta première communauté pour commencer à jouer.": "Create your first community to start playing.",
                "Publique": "Public",
                "Privée": "Private",
                "Public": "Public",
                "Épinglée": "Pinned",
                "Communauté publique": "Public community",
                "Communauté privée": "Private community",
                "Tes communautés": "Your communities",
                "Créer une nouvelle communauté": "Create a new community",
                "Informations publiques": "Public information",
                "Ton pseudo et ta photo de profil sont visibles par les membres qui partagent une communauté avec toi.": "Your username and profile photo are visible to members who share a community with you.",
                "Pseudo": "Username",
                "Photo de profil": "Profile photo",
                "Nombre d'amis": "Number of friends",
                "Toujours public": "Always public",
                "Optionnel": "Optional",
                "Afficher ma langue": "Show my language",
                "Afficher mon classement global": "Show my global ranking",
                "Enregistrer la visibilité": "Save visibility",
                "Amis": "Friends",
                "rechercher par pseudo": "search by username",
                "Utilisateurs bloqués": "Blocked users",
                "Les utilisateurs bloqués disparaissent des communautés partagées, des fils et de la carte.": "Blocked users disappear from shared communities, feeds and the map.",
                "Aucun utilisateur bloqué.": "No blocked users.",
                "Débloquer": "Unblock",
                "Supprimer ce compte ?": "Delete this account?",
                "Cette action est définitive. Ton profil, tes préférences et tes communautés administrées seront supprimés.": "This action is final. Your profile, preferences and administered communities will be deleted.",
                "Aucun ami pour le moment.": "No friends yet.",
                "Mes amis": "My friends",
                "Le nombre d'amis est toujours visible publiquement.": "The number of friends is always publicly visible.",
                "Rechercher un pseudo": "Search a username",
                "Demande d'ami": "Friend request",
                "a accepté ta demande d'ami.": "accepted your friend request.",
                "a refusé ta demande d'ami.": "declined your friend request.",
                "Ajouter": "Add",
                "Rechercher un utilisateur": "Search for a user",
                "Profil public": "Public profile",
                "Envoyer une demande d'ami": "Send friend request",
                "Langue": "Language",
                "Filtres": "Filters",
                "Joueurs": "Players",
                "Aucun joueur": "No players",
                "Le classement sera visible dès qu'il y aura des profils à comparer.": "The leaderboard will appear once there are profiles to compare.",
                "Rejoins une ou plusieurs communautés pour filtrer le classement.": "Join one or more communities to filter the leaderboard.",
                "Classement total activé": "Total leaderboard enabled",
                "Revenir au classement total": "Return to total leaderboard",
                "Nouvelle communauté": "New community",
                "Crée un espace accueillant, règle son tempo et invite tes joueurs.": "Create a welcoming space, set its pace and invite your players.",
                "Nom": "Name",
                "Temps de réponse": "Response time",
                "Heures": "Hours",
                "Minutes": "Minutes",
                "Valide les paramètres et ouvre la communauté.": "Confirm the settings and open the community.",
                "Infos communauté": "Community info",
                "Zone dangereuse": "Danger zone",
                "Supprimer la communauté": "Delete community",
                "Politique de confidentialité": "Privacy policy",
                "Support et contact": "Support and contact",
                "Informations légales et assistance": "Legal information and support",
                "Consulte les informations sur tes données ou contacte directement Torpille.": "Review information about your data or contact Torpille directly.",
                "Suppression en cours…": "Deleting…",
                "Supprimer cette communauté ?": "Delete this community?",
                "Supprimer définitivement": "Delete permanently",
                "La communauté et tous ses contenus, enregistrés ou non, seront supprimés définitivement. Cette action est irréversible.": "The community and all its content, saved or unsaved, will be permanently deleted. This action cannot be undone.",
                "Participants": "Participants",
                "Paramètres": "Settings",
                "Admin": "Admin",
                "Signaler": "Report",
                "Signaler ce contenu": "Report this content",
                "Informations obligatoires": "Required information",
                "Informations facultatives": "Optional information",
                "Prénom": "First name",
                "Nom de famille": "Last name",
                "Ajouter ma date de naissance": "Add my date of birth",
                "Date de naissance": "Date of birth",
                "Ville de domiciliation": "City of residence",
                "Courte présentation": "Short bio",
                "Profil à compléter": "Profile incomplete",
                "Obligatoire pour créer ou rejoindre une communauté :": "Required to create or join a community:",
                "Bloquer cet utilisateur": "Block this user",
                "Bloquer cet utilisateur ?": "Block this user?",
                "Cet utilisateur sera masqué dans l'application. Pour le débloquer, va dans ton profil.": "This user will be hidden in the app. To unblock them, go to your profile.",
                "Masquer ce membre ici": "Hide this member here",
                "Retirer de la communauté": "Remove from community",
                "Bannir": "Ban",
                "Contenus enregistres": "Saved content",
                "Publier en Memories": "Publish to Memories",
                "Retirer des Memories": "Remove from Memories",
                "Aucun contenu enregistre": "No saved content",
                "Torpilles non vues": "Unseen torpilles",
                "Messages non vus": "Unread messages",
                "Écrire un message…": "Write a message...",
                "Qui veux-tu torpiller ?": "Who do you want to torpille?",
                "Choisir la cible": "Choose target",
                "Aucune torpille non vue": "No unseen torpille",
                "Raison": "Reason",
                "Contenu concerné": "Related content",
                "Ajoute un contexte si nécessaire": "Add context if needed",
                "Connectés il y a moins de 30 min": "Connected less than 30 min ago",
                "Mode fantôme": "Ghost mode",
                "Masque ta position et les autres utilisateurs sur la carte.": "Hide your location and other users on the map.",
                "Le mode fantôme est actif : ta position n'est pas partagée et aucun autre utilisateur n'apparaît sur ta carte.": "Ghost mode is active: your location is not shared and no other users appear on your map.",
                "Interprétation": "Interpretation",
                "Message vocal": "Voice message",
                "Lire": "Play",
                "Photo": "Photo",
                "Ouvrir": "Open",
                "Emoji personnalisé": "Custom emoji",
                "Retirer la photo sélectionnée": "Remove selected photo",
                "Formats recommandés : JPG ou PNG.": "Recommended formats: JPG or PNG.",
                "Bienvenue": "Welcome",
                "capitaine": "captain",
                "Réponse en": "Response in",
                "Privé": "Private",
                "Retirer de l’accueil": "Remove from home",
                "Épingler dans l’accueil": "Pin to home",
                "Ouvrir le profil": "Open profile",
                "Enregistrement en cours": "Saving",
                "Se déconnecter ?": "Sign out?",
                "Tu devras te reconnecter pour accéder à ton compte.": "You will need to sign in again to access your account.",
                "Supprimer mon compte": "Delete my account",
                "Suppression du compte en cours": "Deleting account",
                "Visibilité optionnelle": "Optional visibility",
                "Ces informations permettent aux membres de communautés partagées de t'identifier et de demander à devenir ami.": "This information lets members from shared communities identify you and ask to become friends.",
                "Tu peux masquer ta langue et ton classement global à tout moment.": "You can hide your language and global ranking at any time.",
                "Ouvre ton profil, va dans Amis, puis recherche le pseudo de la personne à ajouter.": "Open your profile, go to Friends, then search for the username to add.",
                "Ouvre le profil public de cet ami.": "Open this friend's public profile.",
                "Le pseudo, la photo de profil et le nombre d'amis sont publics. La langue et le classement ne s'affichent ici que si l'utilisateur les a rendus visibles.": "The username, profile photo and friend count are public. Language and ranking only appear here if the user made them visible.",
                "Carte des torpilleurs": "Torpilleurs map",
                "Toutes": "All",
                "Tu n'appartiens encore à aucune communauté.": "You do not belong to any community yet.",
                "Aucun torpilleur géolocalisé": "No geolocated torpilleur",
                "Ouvre la carte avec la localisation autorisée pour publier ta position. Les autres membres apparaîtront dès qu'ils auront aussi partagé une position.": "Open the map with location permission to publish your position. Other members will appear once they have also shared a position.",
                "La carte montre tous les torpilleurs avec qui tu partages au moins une communauté.": "The map shows every torpilleur with whom you share at least one community.",
                "La carte montre uniquement les torpilleurs de la communauté sélectionnée.": "The map only shows torpilleurs from the selected community.",
                "L'heure affichée à côté de l'icône est celle de la dernière torpille de l'utilisateur concerné.": "The time shown next to the icon is the user's latest torpille time.",
                "Choisir une communauté": "Choose a community",
                "Envoi de la torpille…": "Sending torpille...",
                "Invitation communauté": "Community invitation",
                "Patiente un instant pendant que Torpille vérifie ton invitation.": "Wait a moment while Torpille checks your invitation.",
                "Retour à la discussion": "Back to chat",
                "La page d’invitation permet de rejoindre cette communauté.": "The invitation page lets people join this community.",
                "Enregistrer": "Save",
                "Aucun participant pour le moment.": "No participants yet.",
                "OK": "OK",
                "Torpillé en attente": "Pending torpille",
                "Bloquer": "Block",
                "Ajouter comme ami": "Add as friend",
                "Signaler cet utilisateur": "Report this user",
                "Masquer ses contenus ici": "Hide this user's content here",
                "Réafficher ses contenus ici": "Show this user's content again",
                "Maintiens un contenu appuye dans la discussion pour l'enregistrer ici.": "Long-press content in the chat to save it here.",
                "Chargement du media…": "Loading media...",
                "Message texte": "Text message",
                "Image": "Image",
                "Video": "Video",
                "Contenu": "Content",
                "Photo enregistree": "Saved photo",
                "Torpille enregistree": "Saved torpille",
                "Video enregistree": "Saved video",
                "Message vocal enregistre": "Saved voice message",
                "Contenu enregistre": "Saved content",
                "Retirer": "Remove",
                "Publier": "Publish",
                "Pause": "Pause",
                "Ecouter": "Listen",
                "Tout": "All",
                "Seulement moi": "Only me",
                "Arrêter": "Stop",
                "Durée inconnue": "Unknown duration",
                "Vidéo": "Video",
                "Choisir une photo": "Choose a photo",
                "Remplacer la photo": "Replace photo",
                "Tu peux choisir dans la liste ou saisir n'importe quel emoji avec le clavier emoji iOS.": "Choose from the list or enter any emoji with the iOS emoji keyboard.",
                "Aucune nouvelle torpille": "No new torpille",
                "Torpille": "Torpille",
                "Torpilles": "Torpilles",
                "Torpille en attente": "Pending torpille",
                "Filmer la réponse": "Record the reply",
                "Relancer vers": "Send on to",
                "Deja enregistre": "Already saved",
                "Enregistrer dans la discussion": "Save in chat",
                "Date inconnue": "Unknown date",
                "Choisis un membre de cette communauté. Son pseudo et sa photo sont visibles avant l'envoi.": "Choose a member of this community. Their username and profile photo are visible before sending.",
                "Rechercher un membre": "Search a member",
                "Aucun membre ne correspond à cette recherche.": "No member matches this search.",
                "Membre de la communauté. Tu peux accepter, refuser ou passer avant l'envoi.": "Community member. You can accept, decline, or skip before sending.",
                "Passer / choisir un autre membre": "Skip / choose another member",
                "Refuser et annuler": "Decline and cancel",
                "Tu vas connecter cette vidéo à ce membre de la communauté. Aucun envoi anonyme n'est possible.": "You are about to connect this video to this community member. Anonymous sending is not possible.",
                "Les signalements sont examinés rapidement. Les contenus abusifs peuvent être mis en quarantaine, supprimés et entraîner une suspension.": "Reports are reviewed quickly. Abusive content may be quarantined, removed, and lead to suspension.",
                "Les contenus sont automatiquement supprimés après 14 jours, sauf s'ils sont enregistrés dans les contenus enregistrés de la communauté.": "Content is automatically deleted after 14 days unless it has been saved in the community's saved content.",
                "J'accepte l'EULA et les règles de Torpille": "I accept Torpille's EULA and rules",
                "En utilisant Torpille, j'accepte les conditions d'utilisation et reconnais la tolérance zéro pour les contenus sexuels explicites, le harcèlement, les menaces, la haine, le spam et les utilisateurs abusifs. Les contenus signalés peuvent être filtrés, masqués, mis en quarantaine ou supprimés, et les comptes fautifs suspendus ou exclus sous 24 h après examen.": "By using Torpille, I accept the terms of use and acknowledge zero tolerance for explicit sexual content, harassment, threats, hate, spam, and abusive users. Reported content may be filtered, hidden, quarantined, or removed, and offending accounts suspended or excluded within 24 hours after review.",
                "Consulter l'EULA et les règles de modération": "Read the EULA and moderation rules",
                "Tolérance zéro": "Zero tolerance",
                "Torpille n'autorise aucun contenu répréhensible ni comportement abusif. Sont notamment interdits : les contenus sexuels explicites, l'exploitation de mineurs, le harcèlement, les menaces, les discours haineux, la violence, l'usurpation d'identité, le spam et toute utilisation illégale.": "Torpille does not allow objectionable content or abusive behavior. Prohibited material includes explicit sexual content, child exploitation, harassment, threats, hate speech, violence, impersonation, spam, and any illegal use.",
                "Tu dois respecter les autres utilisateurs. Tu peux signaler un contenu ou un compte et bloquer immédiatement un utilisateur. Les signalements sont examinés rapidement ; les contenus concernés peuvent être filtrés, masqués, mis en quarantaine ou supprimés.": "You must respect other users. You can report content or an account and immediately block a user. Reports are reviewed promptly; affected content may be filtered, hidden, quarantined, or removed.",
                "Tout utilisateur qui enfreint ces règles peut voir son contenu supprimé et son compte suspendu ou définitivement exclu. Torpille applique cette politique sans exception aux contenus répréhensibles et aux utilisateurs abusifs.": "Any user who breaks these rules may have their content removed and their account suspended or permanently banned. Torpille enforces this policy without exception for objectionable content and abusive users.",
                "En activant l'acceptation sur l'écran précédent puis en continuant, tu confirmes avoir lu et accepté cet EULA et ces règles de modération.": "By enabling acceptance on the previous screen and continuing, you confirm that you have read and accepted this EULA and these moderation rules.",
                "Retour à la connexion": "Back to sign in",
                "Configuration Firebase requise": "Firebase configuration required",
                "Ajoute le fichier GoogleService-Info.plist iOS dans le groupe Resources du projet Xcode, puis relance l'application.": "Add the iOS GoogleService-Info.plist file to the Xcode project's Resources group, then relaunch the app.",
                "Le projet source peut s'ouvrir immédiatement dans Xcode, mais les fonctions Firebase ne démarreront qu'après l'ajout de ce fichier.": "The source project can open in Xcode immediately, but Firebase features will only start after this file is added.",
                "Utilisateur": "User"
            ],
            .spanish: [
                "Sexe": "Sexo",
                "Homme": "Hombre",
                "Femme": "Mujer",
                "Non binaire": "No binario",
                "Non renseigné": "Sin especificar",
                "Ton adresse email est déjà vérifiée. Tu peux te connecter.": "Tu dirección de correo ya está verificada. Puedes iniciar sesión.",
                "Trop de tentatives. Patiente quelques instants avant de renvoyer un email.": "Demasiados intentos. Espera un momento antes de reenviar un correo.",
                "Continuer": "Continuar",
                "Avant de rejoindre Torpille": "Antes de unirte a Torpille",
                "Lis et accepte les règles EULA et la politique de confidentialité pour accéder à la connexion ou à la création de compte.": "Lee y acepta las reglas EULA y la política de privacidad para iniciar sesión o crear una cuenta.",
                "J’accepte les règles EULA": "Acepto las reglas EULA",
                "Lire la politique de confidentialité": "Leer la política de privacidad",
                "J’accepte la politique de confidentialité": "Acepto la política de privacidad",
                "Les deux acceptations sont obligatoires pour continuer.": "Debes aceptar ambos documentos para continuar.",
                "Revoir mes acceptations": "Revisar mis aceptaciones",
                "Lu et accepté": "Leído y aceptado",
                "Lis et accepte les règles EULA et la politique de confidentialité avant de continuer.": "Lee y acepta las reglas EULA y la política de privacidad antes de continuar.",
                "Conditions obligatoires avant connexion ou inscription": "Condiciones obligatorias antes de iniciar sesión o registrarte",
                "Tu dois ouvrir puis accepter les deux documents sur cet appareil avant de continuer.": "Debes abrir y aceptar ambos documentos en este dispositivo antes de continuar.",
                "Accepté sur cet appareil": "Aceptado en este dispositivo",
                "Ouvrir et accepter": "Abrir y aceptar",
                "Lis et accepte l’EULA et les règles de l’app avant de te connecter.": "Lee y acepta el EULA y las reglas de la app antes de iniciar sesión.",
                "Lis et accepte l’EULA et les règles de l’app avant de créer un compte.": "Lee y acepta el EULA y las reglas de la app antes de crear una cuenta.",
                "Chargement…": "Cargando...",
                "Retour": "Volver",
                "Fermer": "Cerrar",
                "Annuler": "Cancelar",
                "Supprimer": "Eliminar",
                "Envoyer": "Enviar",
                "Créer": "Crear",
                "Création…": "Creando...",
                "Accueil": "Inicio",
                "Communautés": "Comunidades",
                "Profil": "Perfil",
                "Activité": "Actividad",
                "Réglages": "Ajustes",
                "Préférences": "Preferencias",
                "Notifications": "Notificaciones",
                "Les notifications sont automatiquement supprimées après deux semaines.": "Las notificaciones se eliminan automáticamente después de dos semanas.",
                "Aucune communauté": "Ninguna comunidad",
                "Rejoins ou crée une communauté pour configurer tes notifications.": "Únete o crea una comunidad para configurar tus notificaciones.",
                "Choisis si chaque communauté doit te notifier pour tous les contenus ou seulement quand tu es identifié·e.": "Elige si cada comunidad debe notificarte todo el contenido o solo cuando te etiqueten.",
                "Créer une communauté": "Crear una comunidad",
                "Classement global": "Clasificación global",
                "Dernière communauté": "Última comunidad",
                "Communautés épinglées": "Comunidades fijadas",
                "Actions rapides": "Acciones rápidas",
                "Aucune communauté pour le moment.": "Aún no hay comunidades.",
                "Crée ta première communauté pour commencer à jouer.": "Crea tu primera comunidad para empezar a jugar.",
                "Publique": "Pública",
                "Privée": "Privada",
                "Public": "Pública",
                "Privé": "Privada",
                "Épinglée": "Fijada",
                "Communauté publique": "Comunidad pública",
                "Communauté privée": "Comunidad privada",
                "Tes communautés": "Tus comunidades",
                "Informations publiques": "Información pública",
                "Pseudo": "Apodo",
                "Photo de profil": "Foto de perfil",
                "Nombre d'amis": "Número de amigos",
                "Toujours public": "Siempre público",
                "Optionnel": "Opcional",
                "Afficher ma langue": "Mostrar mi idioma",
                "Afficher mon classement global": "Mostrar mi clasificación global",
                "Enregistrer la visibilité": "Guardar visibilidad",
                "Amis": "Amigos",
                "rechercher par pseudo": "buscar por apodo",
                "Utilisateurs bloqués": "Usuarios bloqueados",
                "Les utilisateurs bloqués disparaissent des communautés partagées, des fils et de la carte.": "Los usuarios bloqueados desaparecen de las comunidades compartidas, los hilos y el mapa.",
                "Aucun utilisateur bloqué.": "No hay usuarios bloqueados.",
                "Débloquer": "Desbloquear",
                "Se déconnecter ?": "¿Cerrar sesión?",
                "Tu devras te reconnecter pour accéder à ton compte.": "Tendrás que volver a iniciar sesión para acceder a tu cuenta.",
                "Supprimer ce compte ?": "¿Eliminar esta cuenta?",
                "Cette action est définitive. Ton profil, tes préférences et tes communautés administrées seront supprimés.": "Esta acción es definitiva. Se eliminarán tu perfil, tus preferencias y las comunidades que administras.",
                "Aucun ami pour le moment.": "Aún no hay amigos.",
                "Mes amis": "Mis amigos",
                "Le nombre d'amis est toujours visible publiquement.": "El número de amigos siempre es público.",
                "Rechercher un pseudo": "Buscar un apodo",
                "Ajouter": "Añadir",
                "Rechercher un utilisateur": "Buscar un usuario",
                "Profil public": "Perfil público",
                "Envoyer une demande d'ami": "Enviar solicitud de amistad",
                "Langue": "Idioma",
                "Filtres": "Filtros",
                "Joueurs": "Jugadores",
                "Aucun joueur": "Ningún jugador",
                "Le classement sera visible dès qu'il y aura des profils à comparer.": "La clasificación aparecerá cuando haya perfiles para comparar.",
                "Rejoins une ou plusieurs communautés pour filtrer le classement.": "Únete a una o varias comunidades para filtrar la clasificación.",
                "Classement total activé": "Clasificación total activada",
                "Revenir au classement total": "Volver a la clasificación total",
                "Nouvelle communauté": "Nueva comunidad",
                "Crée un espace accueillant, règle son tempo et invite tes joueurs.": "Crea un espacio acogedor, ajusta su ritmo e invita a tus jugadores.",
                "Nom": "Nombre",
                "Temps de réponse": "Tiempo de respuesta",
                "Heures": "Horas",
                "Minutes": "Minutos",
                "Valide les paramètres et ouvre la communauté.": "Valida los ajustes y abre la comunidad.",
                "Infos communauté": "Info de comunidad",
                "Zone dangereuse": "Zona peligrosa",
                "Supprimer la communauté": "Eliminar la comunidad",
                "Politique de confidentialité": "Política de privacidad",
                "Support et contact": "Soporte y contacto",
                "Informations légales et assistance": "Información legal y asistencia",
                "Consulte les informations sur tes données ou contacte directement Torpille.": "Consulta la información sobre tus datos o contacta directamente con Torpille.",
                "Suppression en cours…": "Eliminando…",
                "Supprimer cette communauté ?": "¿Eliminar esta comunidad?",
                "Supprimer définitivement": "Eliminar permanentemente",
                "La communauté et tous ses contenus, enregistrés ou non, seront supprimés définitivement. Cette action est irréversible.": "La comunidad y todo su contenido, guardado o no, se eliminarán permanentemente. Esta acción no se puede deshacer.",
                "Participants": "Participantes",
                "Paramètres": "Ajustes",
                "Admin": "Admin",
                "Signaler": "Reportar",
                "Signaler ce contenu": "Reportar este contenido",
                "Informations obligatoires": "Información obligatoria",
                "Informations facultatives": "Información opcional",
                "Prénom": "Nombre",
                "Nom de famille": "Apellido",
                "Ajouter ma date de naissance": "Añadir mi fecha de nacimiento",
                "Date de naissance": "Fecha de nacimiento",
                "Ville de domiciliation": "Ciudad de residencia",
                "Courte présentation": "Breve presentación",
                "Profil à compléter": "Perfil incompleto",
                "Obligatoire pour créer ou rejoindre une communauté :": "Obligatorio para crear o unirse a una comunidad:",
                "Bloquer": "Bloquear",
                "Bloquer cet utilisateur": "Bloquear este usuario",
                "Masquer ce membre ici": "Ocultar este miembro aquí",
                "Retirer de la communauté": "Eliminar de la comunidad",
                "Bannir": "Expulsar",
                "Contenus enregistres": "Contenidos guardados",
                "Publier en Memories": "Publicar en Memories",
                "Retirer des Memories": "Quitar de Memories",
                "Aucun contenu enregistre": "No hay contenido guardado",
                "Torpilles non vues": "Torpilles no vistas",
                "Messages non vus": "Mensajes no leídos",
                "Écrire un message…": "Escribir un mensaje...",
                "Qui veux-tu torpiller ?": "¿A quién quieres torpillear?",
                "Choisir la cible": "Elegir objetivo",
                "Aucune torpille non vue": "Ninguna torpille no vista",
                "Raison": "Motivo",
                "Contenu concerné": "Contenido afectado",
                "Ajoute un contexte si nécessaire": "Añade contexto si hace falta",
                "Connectés il y a moins de 30 min": "Conectados hace menos de 30 min",
                "Mode fantôme": "Modo fantasma",
                "Masque ta position et les autres utilisateurs sur la carte.": "Oculta tu ubicación y a los demás usuarios del mapa.",
                "Le mode fantôme est actif : ta position n'est pas partagée et aucun autre utilisateur n'apparaît sur ta carte.": "El modo fantasma está activo: tu ubicación no se comparte y ningún otro usuario aparece en tu mapa.",
                "Interprétation": "Interpretación",
                "Message vocal": "Mensaje de voz",
                "Carte des torpilleurs": "Mapa de torpilleurs",
                "Toutes": "Todas",
                "Aucun torpilleur géolocalisé": "Ningún torpilleur geolocalizado",
                "Retour à la discussion": "Volver al chat",
                "Aucun participant pour le moment.": "Aún no hay participantes.",
                "OK": "OK",
                "Torpillé en attente": "Torpille pendiente",
                "Maintiens un contenu appuye dans la discussion pour l'enregistrer ici.": "Mantén pulsado un contenido en el chat para guardarlo aquí.",
                "Message texte": "Mensaje de texto",
                "Image": "Imagen",
                "Video": "Vídeo",
                "Contenu": "Contenido",
                "Retirer": "Quitar",
                "Publier": "Publicar",
                "Pause": "Pausa",
                "Ecouter": "Escuchar",
                "Tout": "Todo",
                "Seulement moi": "Solo yo",
                "Lire": "Reproducir",
                "Arrêter": "Detener",
                "Durée inconnue": "Duración desconocida",
                "Vidéo": "Vídeo",
                "Photo": "Foto",
                "Ouvrir": "Abrir",
                "Emoji personnalisé": "Emoji personalizado",
                "Choisir une photo": "Elegir una foto",
                "Remplacer la photo": "Reemplazar la foto",
                "Tu peux choisir dans la liste ou saisir n'importe quel emoji avec le clavier emoji iOS.": "Puedes elegir en la lista o escribir cualquier emoji con el teclado emoji de iOS.",
                "Aucune nouvelle torpille": "Ninguna torpille nueva",
                "Torpille": "Torpille",
                "Torpilles": "Torpilles",
                "Torpille en attente": "Torpille pendiente",
                "Filmer la réponse": "Grabar la respuesta",
                "Relancer vers": "Reenviar a",
                "Deja enregistre": "Ya guardado",
                "Enregistrer dans la discussion": "Guardar en el chat",
                "Date inconnue": "Fecha desconocida",
                "Choisis un membre de cette communauté. Son pseudo et sa photo sont visibles avant l'envoi.": "Elige un miembro de esta comunidad. Su apodo y foto de perfil son visibles antes del envío.",
                "Rechercher un membre": "Buscar un miembro",
                "Aucun membre ne correspond à cette recherche.": "Ningún miembro coincide con esta búsqueda.",
                "Membre de la communauté. Tu peux accepter, refuser ou passer avant l'envoi.": "Miembro de la comunidad. Puedes aceptar, rechazar o pasar antes de enviar.",
                "Passer / choisir un autre membre": "Pasar / elegir otro miembro",
                "Refuser et annuler": "Rechazar y cancelar",
                "Tu vas connecter cette vidéo à ce membre de la communauté. Aucun envoi anonyme n'est possible.": "Vas a conectar este vídeo con este miembro de la comunidad. No es posible enviarlo de forma anónima.",
                "Les signalements sont examinés rapidement. Les contenus abusifs peuvent être mis en quarantaine, supprimés et entraîner une suspension.": "Los reportes se revisan rápidamente. El contenido abusivo puede ponerse en cuarentena, eliminarse y provocar una suspensión.",
                "Les contenus sont automatiquement supprimés après 14 jours, sauf s'ils sont enregistrés dans les contenus enregistrés de la communauté.": "Los contenidos se eliminan automáticamente después de 14 días salvo que estén guardados en los contenidos guardados de la comunidad.",
                "J'accepte l'EULA et les règles de Torpille": "Acepto las reglas EULA y la política de privacidad",
                "En utilisant Torpille, j'accepte les conditions d'utilisation et reconnais la tolérance zéro pour les contenus sexuels explicites, le harcèlement, les menaces, la haine, le spam et les utilisateurs abusifs. Les contenus signalés peuvent être filtrés, masqués, mis en quarantaine ou supprimés, et les comptes fautifs suspendus ou exclus sous 24 h après examen.": "Al usar Torpille, acepto las condiciones de uso y reconozco la tolerancia cero con contenido sexual explícito, acoso, amenazas, odio, spam y usuarios abusivos. El contenido reportado puede filtrarse, ocultarse, ponerse en cuarentena o eliminarse, y las cuentas infractoras pueden suspenderse o excluirse en 24 h tras la revisión.",
                "Consulter l'EULA et les règles de modération": "Consultar el EULA y las reglas de moderación",
                "Tolérance zéro": "Tolerancia cero",
                "Torpille n'autorise aucun contenu répréhensible ni comportement abusif. Sont notamment interdits : les contenus sexuels explicites, l'exploitation de mineurs, le harcèlement, les menaces, les discours haineux, la violence, l'usurpation d'identité, le spam et toute utilisation illégale.": "Torpille no permite contenido objetable ni conductas abusivas. Se prohíben, entre otros, el contenido sexual explícito, la explotación infantil, el acoso, las amenazas, el odio, la violencia, la suplantación, el spam y cualquier uso ilegal.",
                "Tu dois respecter les autres utilisateurs. Tu peux signaler un contenu ou un compte et bloquer immédiatement un utilisateur. Les signalements sont examinés rapidement ; les contenus concernés peuvent être filtrés, masqués, mis en quarantaine ou supprimés.": "Debes respetar a los demás usuarios. Puedes denunciar contenido o una cuenta y bloquear inmediatamente a un usuario. Las denuncias se revisan rápidamente; el contenido puede filtrarse, ocultarse, ponerse en cuarentena o eliminarse.",
                "Tout utilisateur qui enfreint ces règles peut voir son contenu supprimé et son compte suspendu ou définitivement exclu. Torpille applique cette politique sans exception aux contenus répréhensibles et aux utilisateurs abusifs.": "Cualquier usuario que infrinja estas reglas puede ver su contenido eliminado y su cuenta suspendida o expulsada permanentemente. Torpille aplica esta política sin excepciones al contenido objetable y a los usuarios abusivos.",
                "En activant l'acceptation sur l'écran précédent puis en continuant, tu confirmes avoir lu et accepté cet EULA et ces règles de modération.": "Al activar la aceptación en la pantalla anterior y continuar, confirmas que has leído y aceptado este EULA y estas reglas de moderación.",
                "Retour à la connexion": "Volver al inicio de sesión",
                "Configuration Firebase requise": "Configuración de Firebase requerida",
                "Ajoute le fichier GoogleService-Info.plist iOS dans le groupe Resources du projet Xcode, puis relance l'application.": "Añade el archivo iOS GoogleService-Info.plist al grupo Resources del proyecto Xcode y reinicia la app.",
                "Le projet source peut s'ouvrir immédiatement dans Xcode, mais les fonctions Firebase ne démarreront qu'après l'ajout de ce fichier.": "El proyecto fuente puede abrirse inmediatamente en Xcode, pero las funciones de Firebase no arrancarán hasta añadir este archivo.",
                "Utilisateur": "Usuario"
            ],
            .german: [
                "Sexe": "Geschlecht",
                "Homme": "Mann",
                "Femme": "Frau",
                "Non binaire": "Nichtbinär",
                "Non renseigné": "Keine Angabe",
                "Ton adresse email est déjà vérifiée. Tu peux te connecter.": "Deine E-Mail-Adresse ist bereits bestätigt. Du kannst dich anmelden.",
                "Trop de tentatives. Patiente quelques instants avant de renvoyer un email.": "Zu viele Versuche. Warte etwas, bevor du erneut eine E-Mail anforderst.",
                "Continuer": "Weiter",
                "Avant de rejoindre Torpille": "Bevor du Torpille beitrittst",
                "Lis et accepte les règles EULA et la politique de confidentialité pour accéder à la connexion ou à la création de compte.": "Lies und akzeptiere die EULA-Regeln und die Datenschutzerklärung, um dich anzumelden oder ein Konto zu erstellen.",
                "J’accepte les règles EULA": "Ich akzeptiere die EULA-Regeln",
                "Lire la politique de confidentialité": "Datenschutzerklärung lesen",
                "J’accepte la politique de confidentialité": "Ich akzeptiere die Datenschutzerklärung",
                "Les deux acceptations sont obligatoires pour continuer.": "Beide Zustimmungen sind erforderlich, um fortzufahren.",
                "Revoir mes acceptations": "Meine Zustimmungen prüfen",
                "Lu et accepté": "Gelesen und akzeptiert",
                "Lis et accepte les règles EULA et la politique de confidentialité avant de continuer.": "Lies und akzeptiere die EULA-Regeln und die Datenschutzerklärung, bevor du fortfährst.",
                "Politique de confidentialité": "Datenschutzerklärung",
                "Support et contact": "Support und Kontakt",
                "Informations légales et assistance": "Rechtliche Informationen und Hilfe",
                "Consulte les informations sur tes données ou contacte directement Torpille.": "Informiere dich über deine Daten oder kontaktiere Torpille direkt.",
                "Zone dangereuse": "Gefahrenbereich",
                "Supprimer la communauté": "Community löschen",
                "Suppression en cours…": "Wird gelöscht…",
                "Supprimer cette communauté ?": "Diese Community löschen?",
                "Supprimer définitivement": "Endgültig löschen",
                "La communauté et tous ses contenus, enregistrés ou non, seront supprimés définitivement. Cette action est irréversible.": "Die Community und alle gespeicherten oder nicht gespeicherten Inhalte werden endgültig gelöscht. Dies kann nicht rückgängig gemacht werden.",
                "Conditions obligatoires avant connexion ou inscription": "Pflichtbedingungen vor Anmeldung oder Registrierung",
                "Tu dois ouvrir puis accepter les deux documents sur cet appareil avant de continuer.": "Du musst beide Dokumente auf diesem Gerät öffnen und akzeptieren, bevor du fortfährst.",
                "Accepté sur cet appareil": "Auf diesem Gerät akzeptiert",
                "Ouvrir et accepter": "Öffnen und akzeptieren",
                "Lis et accepte l’EULA et les règles de l’app avant de te connecter.": "Lies und akzeptiere die EULA und App-Regeln vor der Anmeldung.",
                "Lis et accepte l’EULA et les règles de l’app avant de créer un compte.": "Lies und akzeptiere die EULA und App-Regeln, bevor du ein Konto erstellst.",
                "Annuler": "Abbrechen",
                "Aucune communauté": "Keine Community",
                "Carte des torpilleurs": "Torpilleurs-Karte",
                "Toutes": "Alle",
                "Tu n'appartiens encore à aucune communauté.": "Du gehörst noch keiner Community an.",
                "Connectés il y a moins de 30 min": "Vor weniger als 30 Minuten aktiv",
                "Mode fantôme": "Geistermodus",
                "Masque ta position et les autres utilisateurs sur la carte.": "Blendet deinen Standort und andere Nutzer auf der Karte aus.",
                "Interprétation": "Erläuterung",
                "Le mode fantôme est actif : ta position n'est pas partagée et aucun autre utilisateur n'apparaît sur ta carte.": "Der Geistermodus ist aktiv: Dein Standort wird nicht geteilt und andere Nutzer erscheinen nicht auf deiner Karte.",
                "La carte montre tous les torpilleurs avec qui tu partages au moins une communauté.": "Die Karte zeigt alle Torpilleurs, mit denen du mindestens eine Community teilst.",
                "La carte montre uniquement les torpilleurs de la communauté sélectionnée.": "Die Karte zeigt nur die Torpilleurs der ausgewählten Community.",
                "L'heure affichée à côté de l'icône est celle de la dernière torpille de l'utilisateur concerné.": "Die Uhrzeit neben dem Symbol zeigt die letzte Torpille des jeweiligen Nutzers.",
                "Choisir une communauté": "Community auswählen",
                "Envoi de la torpille…": "Torpille wird gesendet…"
            ],
            .italian: [
                "Sexe": "Sesso",
                "Homme": "Uomo",
                "Femme": "Donna",
                "Non binaire": "Non binario",
                "Non renseigné": "Non specificato",
                "Ton adresse email est déjà vérifiée. Tu peux te connecter.": "Il tuo indirizzo email è già verificato. Puoi accedere.",
                "Trop de tentatives. Patiente quelques instants avant de renvoyer un email.": "Troppi tentativi. Attendi un po’ prima di inviare di nuovo un’email.",
                "Continuer": "Continua",
                "Avant de rejoindre Torpille": "Prima di entrare in Torpille",
                "Lis et accepte les règles EULA et la politique de confidentialité pour accéder à la connexion ou à la création de compte.": "Leggi e accetta le regole EULA e l’informativa sulla privacy per accedere o creare un account.",
                "J’accepte les règles EULA": "Accetto le regole EULA",
                "Lire la politique de confidentialité": "Leggi l’informativa sulla privacy",
                "J’accepte la politique de confidentialité": "Accetto l’informativa sulla privacy",
                "Les deux acceptations sont obligatoires pour continuer.": "Entrambe le accettazioni sono obbligatorie per continuare.",
                "Revoir mes acceptations": "Rivedi le mie accettazioni",
                "Lu et accepté": "Letto e accettato",
                "Lis et accepte les règles EULA et la politique de confidentialité avant de continuer.": "Leggi e accetta le regole EULA e l’informativa sulla privacy prima di continuare.",
                "Politique de confidentialité": "Informativa sulla privacy",
                "Support et contact": "Assistenza e contatti",
                "Informations légales et assistance": "Informazioni legali e assistenza",
                "Consulte les informations sur tes données ou contacte directement Torpille.": "Consulta le informazioni sui tuoi dati o contatta direttamente Torpille.",
                "Zone dangereuse": "Zona pericolosa",
                "Supprimer la communauté": "Elimina la comunità",
                "Suppression en cours…": "Eliminazione…",
                "Supprimer cette communauté ?": "Eliminare questa comunità?",
                "Supprimer définitivement": "Elimina definitivamente",
                "La communauté et tous ses contenus, enregistrés ou non, seront supprimés définitivement. Cette action est irréversible.": "La comunità e tutti i contenuti, salvati o meno, verranno eliminati definitivamente. Questa azione non può essere annullata.",
                "Conditions obligatoires avant connexion ou inscription": "Condizioni obbligatorie prima dell’accesso o della registrazione",
                "Tu dois ouvrir puis accepter les deux documents sur cet appareil avant de continuer.": "Devi aprire e accettare entrambi i documenti su questo dispositivo prima di continuare.",
                "Accepté sur cet appareil": "Accettato su questo dispositivo",
                "Ouvrir et accepter": "Apri e accetta",
                "Lis et accepte l’EULA et les règles de l’app avant de te connecter.": "Leggi e accetta l’EULA e le regole dell’app prima di accedere.",
                "Lis et accepte l’EULA et les règles de l’app avant de créer un compte.": "Leggi e accetta l’EULA e le regole dell’app prima di creare un account.",
                "Annuler": "Annulla",
                "Aucune communauté": "Nessuna community",
                "Carte des torpilleurs": "Mappa dei torpilleurs",
                "Toutes": "Tutte",
                "Tu n'appartiens encore à aucune communauté.": "Non appartieni ancora a nessuna community.",
                "Connectés il y a moins de 30 min": "Attivi meno di 30 minuti fa",
                "Mode fantôme": "Modalità fantasma",
                "Masque ta position et les autres utilisateurs sur la carte.": "Nasconde la tua posizione e gli altri utenti sulla mappa.",
                "Interprétation": "Spiegazione",
                "Le mode fantôme est actif : ta position n'est pas partagée et aucun autre utilisateur n'apparaît sur ta carte.": "La modalità fantasma è attiva: la tua posizione non viene condivisa e nessun altro utente appare sulla mappa.",
                "La carte montre tous les torpilleurs avec qui tu partages au moins une communauté.": "La mappa mostra tutti i torpilleurs con cui condividi almeno una community.",
                "La carte montre uniquement les torpilleurs de la communauté sélectionnée.": "La mappa mostra solo i torpilleurs della community selezionata.",
                "L'heure affichée à côté de l'icône est celle de la dernière torpille de l'utilisateur concerné.": "L'ora accanto all'icona indica l'ultima torpille dell'utente.",
                "Choisir une communauté": "Scegli una community",
                "Envoi de la torpille…": "Invio della torpille…"
            ],
            .portuguese: [
                "Sexe": "Sexo",
                "Homme": "Homem",
                "Femme": "Mulher",
                "Non binaire": "Não binário",
                "Non renseigné": "Não informado",
                "Ton adresse email est déjà vérifiée. Tu peux te connecter.": "Seu endereço de email já foi verificado. Você pode entrar.",
                "Trop de tentatives. Patiente quelques instants avant de renvoyer un email.": "Muitas tentativas. Aguarde um pouco antes de reenviar um email.",
                "Continuer": "Continuar",
                "Avant de rejoindre Torpille": "Antes de entrar no Torpille",
                "Lis et accepte les règles EULA et la politique de confidentialité pour accéder à la connexion ou à la création de compte.": "Leia e aceite as regras EULA e a política de privacidade para entrar ou criar uma conta.",
                "J’accepte les règles EULA": "Aceito as regras EULA",
                "Lire la politique de confidentialité": "Ler a política de privacidade",
                "J’accepte la politique de confidentialité": "Aceito a política de privacidade",
                "Les deux acceptations sont obligatoires pour continuer.": "É necessário aceitar os dois documentos para continuar.",
                "Revoir mes acceptations": "Rever minhas aceitações",
                "Lu et accepté": "Lido e aceito",
                "Lis et accepte les règles EULA et la politique de confidentialité avant de continuer.": "Leia e aceite as regras EULA e a política de privacidade antes de continuar.",
                "Politique de confidentialité": "Política de privacidade",
                "Support et contact": "Suporte e contato",
                "Informations légales et assistance": "Informações legais e suporte",
                "Consulte les informations sur tes données ou contacte directement Torpille.": "Consulte as informações sobre seus dados ou entre em contato diretamente com o Torpille.",
                "Zone dangereuse": "Zona de perigo",
                "Supprimer la communauté": "Excluir a comunidade",
                "Suppression en cours…": "Excluindo…",
                "Supprimer cette communauté ?": "Excluir esta comunidade?",
                "Supprimer définitivement": "Excluir permanentemente",
                "La communauté et tous ses contenus, enregistrés ou non, seront supprimés définitivement. Cette action est irréversible.": "A comunidade e todo o conteúdo, salvo ou não, serão excluídos permanentemente. Esta ação não pode ser desfeita.",
                "Conditions obligatoires avant connexion ou inscription": "Termos obrigatórios antes de entrar ou se cadastrar",
                "Tu dois ouvrir puis accepter les deux documents sur cet appareil avant de continuer.": "Você deve abrir e aceitar ambos os documentos neste dispositivo antes de continuar.",
                "Accepté sur cet appareil": "Aceito neste dispositivo",
                "Ouvrir et accepter": "Abrir e aceitar",
                "Lis et accepte l’EULA et les règles de l’app avant de te connecter.": "Leia e aceite o EULA e as regras do app antes de entrar.",
                "Lis et accepte l’EULA et les règles de l’app avant de créer un compte.": "Leia e aceite o EULA e as regras do app antes de criar uma conta.",
                "Annuler": "Cancelar",
                "Aucune communauté": "Nenhuma comunidade",
                "Carte des torpilleurs": "Mapa dos torpilleurs",
                "Toutes": "Todas",
                "Tu n'appartiens encore à aucune communauté.": "Você ainda não pertence a nenhuma comunidade.",
                "Connectés il y a moins de 30 min": "Ativos há menos de 30 minutos",
                "Mode fantôme": "Modo fantasma",
                "Masque ta position et les autres utilisateurs sur la carte.": "Oculta sua localização e os outros usuários no mapa.",
                "Interprétation": "Explicação",
                "Le mode fantôme est actif : ta position n'est pas partagée et aucun autre utilisateur n'apparaît sur ta carte.": "O modo fantasma está ativo: sua localização não é compartilhada e nenhum outro usuário aparece no mapa.",
                "La carte montre tous les torpilleurs avec qui tu partages au moins une communauté.": "O mapa mostra todos os torpilleurs com quem você compartilha pelo menos uma comunidade.",
                "La carte montre uniquement les torpilleurs de la communauté sélectionnée.": "O mapa mostra apenas os torpilleurs da comunidade selecionada.",
                "L'heure affichée à côté de l'icône est celle de la dernière torpille de l'utilisateur concerné.": "O horário ao lado do ícone indica a última torpille do usuário.",
                "Choisir une communauté": "Escolher uma comunidade",
                "Envoi de la torpille…": "Enviando a torpille…"
            ]
        ]
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
        case .authWelcomeTitle: return "Bienvenue dans tes communautés privées"
        case .authWelcomeSubtitle: return "Torpille relie des membres identifiés dans des communautés choisies, avec modération, blocage et signalement."
        case .authSectionTitle: return "Connexion"
        case .authSectionSubtitle: return "Entre tes identifiants pour rejoindre tes communautés."
        case .authEmailPlaceholder: return "Email"
        case .authPasswordPlaceholder: return "Mot de passe"
        case .authConfirmPasswordPlaceholder: return "Confirmer le mot de passe"
        case .authPasswordsMismatch: return "Les deux mots de passe ne correspondent pas."
        case .authSignIn: return "Se connecter"
        case .authSignInSubtitle: return "Récupère ton compte et retrouve tes parties en quelques secondes."
        case .authSignUp: return "Créer un compte"
        case .authSignUpSubtitle: return "Clique ici si tu n'as pas encore de compte."
        case .authForgotPassword: return "Mot de passe oublié"
        case .authForgotPasswordSubtitle: return "Reçois un email pour reprendre l'accès à ton compte."
        case .authLoading: return "Chargement…"
        case .profileSetupTitle: return "Crée ton profil"
        case .profileSetupSubtitle: return "Ajoute un pseudo et un avatar visibles pour échanger sans anonymat avec les membres de tes communautés."
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
        case .authWelcomeTitle: return "Welcome to your private communities"
        case .authWelcomeSubtitle: return "Torpille connects identified members inside chosen communities, with moderation, blocking, and reporting."
        case .authSectionTitle: return "Sign in"
        case .authSectionSubtitle: return "Enter your credentials to join your communities."
        case .authEmailPlaceholder: return "Email"
        case .authPasswordPlaceholder: return "Password"
        case .authConfirmPasswordPlaceholder: return "Confirm password"
        case .authPasswordsMismatch: return "The two passwords do not match."
        case .authSignIn: return "Sign in"
        case .authSignInSubtitle: return "Get your account back and return to your games in seconds."
        case .authSignUp: return "Create an account"
        case .authSignUpSubtitle: return "Tap here if you don't have an account yet."
        case .authForgotPassword: return "Forgot password"
        case .authForgotPasswordSubtitle: return "Receive an email to recover access to your account."
        case .authLoading: return "Loading…"
        case .profileSetupTitle: return "Create your profile"
        case .profileSetupSubtitle: return "Add a visible username and avatar so community members are not anonymous."
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
        case .authWelcomeTitle: return "Bienvenido a tus comunidades privadas"
        case .authWelcomeSubtitle: return "Torpille conecta miembros identificados dentro de comunidades elegidas, con moderación, bloqueo y reportes."
        case .authSectionTitle: return "Conexión"
        case .authSectionSubtitle: return "Introduce tus credenciales para unirte a tus comunidades."
        case .authEmailPlaceholder: return "Correo electrónico"
        case .authPasswordPlaceholder: return "Contraseña"
        case .authConfirmPasswordPlaceholder: return "Confirmar contraseña"
        case .authPasswordsMismatch: return "Las dos contraseñas no coinciden."
        case .authSignIn: return "Iniciar sesión"
        case .authSignInSubtitle: return "Recupera tu cuenta y vuelve a tus partidas en segundos."
        case .authSignUp: return "Crear una cuenta"
        case .authSignUpSubtitle: return "Pulsa aquí si todavía no tienes una cuenta."
        case .authForgotPassword: return "Olvidé mi contraseña"
        case .authForgotPasswordSubtitle: return "Recibe un correo para recuperar el acceso a tu cuenta."
        case .authLoading: return "Cargando…"
        case .profileSetupTitle: return "Crea tu perfil"
        case .profileSetupSubtitle: return "Añade un apodo y un avatar visibles para evitar perfiles anónimos en tus comunidades."
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
        case .authWelcomeTitle: return "Willkommen in deinen privaten Communities"
        case .authWelcomeSubtitle: return "Torpille verbindet identifizierte Mitglieder in ausgewählten Communities, mit Moderation, Blockieren und Melden."
        case .authSectionTitle: return "Anmeldung"
        case .authSectionSubtitle: return "Gib deine Zugangsdaten ein, um deinen Communitys beizutreten."
        case .authEmailPlaceholder: return "E-Mail"
        case .authPasswordPlaceholder: return "Passwort"
        case .authConfirmPasswordPlaceholder: return "Passwort bestätigen"
        case .authPasswordsMismatch: return "Die beiden Passwörter stimmen nicht überein."
        case .authSignIn: return "Anmelden"
        case .authSignInSubtitle: return "Hol dir dein Konto zurück und kehre in Sekunden zu deinen Runden zurück."
        case .authSignUp: return "Konto erstellen"
        case .authSignUpSubtitle: return "Tippe hier, wenn du noch kein Konto hast."
        case .authForgotPassword: return "Passwort vergessen"
        case .authForgotPasswordSubtitle: return "Erhalte eine E-Mail, um wieder Zugriff auf dein Konto zu bekommen."
        case .authLoading: return "Lädt…"
        case .profileSetupTitle: return "Erstelle dein Profil"
        case .profileSetupSubtitle: return "Füge einen sichtbaren Nutzernamen und Avatar hinzu, damit Community-Mitglieder nicht anonym bleiben."
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
        case .authWelcomeTitle: return "Benvenuto nelle tue comunità private"
        case .authWelcomeSubtitle: return "Torpille collega membri identificati in comunità scelte, con moderazione, blocco e segnalazioni."
        case .authSectionTitle: return "Accesso"
        case .authSectionSubtitle: return "Inserisci le tue credenziali per entrare nelle tue community."
        case .authEmailPlaceholder: return "Email"
        case .authPasswordPlaceholder: return "Password"
        case .authConfirmPasswordPlaceholder: return "Conferma password"
        case .authPasswordsMismatch: return "Le due password non corrispondono."
        case .authSignIn: return "Accedi"
        case .authSignInSubtitle: return "Recupera il tuo account e torna alle tue partite in pochi secondi."
        case .authSignUp: return "Crea un account"
        case .authSignUpSubtitle: return "Tocca qui se non hai ancora un account."
        case .authForgotPassword: return "Password dimenticata"
        case .authForgotPasswordSubtitle: return "Ricevi un'email per recuperare l'accesso al tuo account."
        case .authLoading: return "Caricamento…"
        case .profileSetupTitle: return "Crea il tuo profilo"
        case .profileSetupSubtitle: return "Aggiungi un nome utente e un avatar visibili per evitare profili anonimi nelle comunità."
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
        case .authWelcomeTitle: return "Bem-vindo às suas comunidades privadas"
        case .authWelcomeSubtitle: return "Torpille conecta membros identificados em comunidades escolhidas, com moderação, bloqueio e denúncias."
        case .authSectionTitle: return "Entrar"
        case .authSectionSubtitle: return "Digite suas credenciais para entrar nas suas comunidades."
        case .authEmailPlaceholder: return "Email"
        case .authPasswordPlaceholder: return "Senha"
        case .authConfirmPasswordPlaceholder: return "Confirmar senha"
        case .authPasswordsMismatch: return "As duas senhas não coincidem."
        case .authSignIn: return "Entrar"
        case .authSignInSubtitle: return "Recupere sua conta e volte para suas partidas em segundos."
        case .authSignUp: return "Criar conta"
        case .authSignUpSubtitle: return "Toque aqui se você ainda não tem uma conta."
        case .authForgotPassword: return "Esqueci minha senha"
        case .authForgotPasswordSubtitle: return "Receba um email para recuperar o acesso à sua conta."
        case .authLoading: return "Carregando…"
        case .profileSetupTitle: return "Crie seu perfil"
        case .profileSetupSubtitle: return "Adicione um nome e avatar visíveis para evitar perfis anônimos nas comunidades."
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
