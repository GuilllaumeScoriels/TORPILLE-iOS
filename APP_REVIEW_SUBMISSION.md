# Préparation de la prochaine soumission App Store

Ce document complète les changements techniques. Les actions App Store Connect ci-dessous restent obligatoires pour que l'équipe Apple puisse constater les mécanismes dans une version TestFlight construite après ces changements.

## Métadonnées App Store Connect

- URL de politique de confidentialité : https://torpille-38783.web.app/privacy.html
- URL d'assistance : https://torpille-38783.web.app/support.html
- Fournir un compte de démonstration vérifié, avec un profil complet, membre d'au moins une communauté contenant deux utilisateurs et quelques contenus de test.
- Fournir un second compte de test afin que le reviewer puisse démontrer le blocage et le signalement sans utiliser de données personnelles réelles.
- Vérifier que les réponses « Confidentialité de l'app » correspondent aux données déclarées dans `TorpilleIOS/Resources/PrivacyInfo.xcprivacy`.
- Choisir une classification d'âge cohérente avec la présence de contenu généré par les utilisateurs et de messagerie.

## Notes proposées à l'équipe App Review

Torpille inclut désormais toutes les protections demandées pour le contenu généré par les utilisateurs.

1. L'EULA et les règles de la communauté sont présentées avant toute inscription ou connexion. Les deux documents doivent être ouverts, lus jusqu'en bas et acceptés séparément. L'acceptation est enregistrée sur l'appareil : une connexion depuis un nouvel appareil impose donc une nouvelle acceptation avant l'authentification.
2. L'EULA précise une tolérance zéro envers le contenu répréhensible et les utilisateurs abusifs.
3. Chaque contenu et chaque profil concerné propose une action « Signaler ». Le signalement permet de choisir un motif et d'ajouter des détails.
4. Chaque utilisateur concerné peut être bloqué immédiatement. Le contenu et les interactions entre les deux comptes sont ensuite masqués dans les deux sens. La liste des comptes bloqués se trouve dans Profil.
5. Un filtre lexical est appliqué aux contenus texte. Il ne sanctionne jamais un utilisateur. Une quarantaine automatique n'est possible que lorsque le contenu a été signalé ET contient un terme de la liste bannie. La suppression du contenu et l'exclusion de l'auteur exigent toujours la décision authentifiée d'un opérateur humain.
6. Les signalements déclenchent une notification de modération et sont suivis avec une échéance de 24 heures.
7. La suppression de compte est disponible dans Profil et supprime le compte ainsi que les contenus associés.
8. L'administrateur d'une communauté peut choisir « Supprimer la communauté ». Une confirmation explique le caractère définitif et irréversible, puis les documents et médias de la communauté sont supprimés côté serveur.
9. La demande de localisation n'apparaît plus au démarrage. Elle est déclenchée seulement lorsque l'utilisateur ouvre la carte ou désactive le mode fantôme. Le texte système explique précisément le partage de la dernière position avec les membres des communautés.

Chemins de démonstration :

- EULA : lancer l'app sur un appareil neuf ou supprimer/réinstaller l'app, puis atteindre l'écran de connexion.
- Signalement/blocage : Communauté > contenu ou membre > menu d'actions > Signaler / Bloquer.
- Comptes bloqués : Profil > Utilisateurs bloqués.
- Suppression de compte : Profil > Supprimer mon compte.
- Suppression de communauté : Communauté administrée > Gérer la communauté > Supprimer la communauté.
- Politique de confidentialité et support : écran d'authentification, puis Profil > Informations légales et assistance.

## Vidéo à joindre à la soumission

Enregistrer sur un appareil physique, sans montage qui masque les transitions :

1. première ouverture ou réinstallation ;
2. affichage de l'EULA avant les boutons de connexion et d'inscription ;
3. impossibilité de continuer tant que les deux textes ne sont pas acceptés ;
4. connexion, ouverture d'un contenu, signalement avec motif ;
5. blocage d'un autre utilisateur et disparition de ses interactions ;
6. affichage de la liste des comptes bloqués ;
7. pour un compte administrateur, dialogue de suppression définitive de communauté ;
8. accès aux pages Confidentialité et Support.

Joindre la vidéo dans le champ Notes de la section App Review Information.

## Vérifications avant envoi

- Construire l'archive depuis un commit contenant `PrivacyInfo.xcprivacy` et les nouveaux purpose strings.
- Installer exactement la build soumise via TestFlight sur un appareil physique.
- Tester inscription, reconnexion après réinstallation, signalement, blocage, déblocage, suppression de compte et suppression de communauté.
- Confirmer que l'adresse `torpille.app@gmail.com` est surveillée et que chaque signalement est examiné en moins de 24 heures.
- Confirmer qu'au moins un compte opérateur est autorisé à appeler `resolveModerationReport` via `MODERATOR_UIDS`.
- Vérifier les journaux Firebase après chaque scénario et conserver les identifiants de signalement.

Apple garde la décision finale de review. Ces vérifications réduisent les causes connues de rejet, mais ne constituent pas une garantie d'acceptation.
