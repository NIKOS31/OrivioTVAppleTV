# Sources, recherches récentes et suggestion de reprise

Ces changements sont présents dans les sources locales. Compilation tvOS et
validation à la télécommande restent requises avant livraison.

## Sources

- « Pas encore sorti » utilise une date connue du titre ou de l’épisode.
  Une date absente ne prouve jamais une sortie à venir.
- « Aucune source trouvée » correspond aux addons répondant sans lien lisible.
- Une panne totale et une réponse partielle ont des messages distincts.
  Les deux configurations d’un même addon sont comptées séparément.
- Des liens éliminés par les filtres ne deviennent pas une panne d’addon.
- Réessayer et les réglages d’addons restent accessibles à la télécommande.
- Les erreurs affichées/journalisées dans ce parcours utilisent des raisons
  fixes françaises, sans réinjecter l’URL ou le `userInfo` d’une erreur réseau.

## Recherches récentes

Huit titres au maximum par profil, dans les préférences locales de l’appareil,
sans ajout au format de synchronisation du compte et sans journalisation.
L’historique apparaît quand le champ est vide. Un clic relance la recherche ;
un appui prolongé permet de la supprimer ; « Tout effacer » vide ce profil.
La suppression d’un profil retire aussi sa clé locale.
La hauteur de la rangée est bornée pour conserver la place des affiches.
Sélectionner une recherche ou vider la rangée rend le focus au champ, sans
ouvrir automatiquement le clavier.

Une recherche est retenue à la validation de la saisie ou à l’ouverture d’un
résultat, jamais à chaque lettre. Annuler la saisie n’enregistre pas le texte.
URLs, adresses mail, marqueurs de secrets et longues chaînes opaques sont
refusés dans l’historique. Ce filtrage ne remplace pas un coffre de secrets.

## Carte de reprise

Sur l’accueil nTV, une petite carte propose le dernier contenu réellement
commencé : au moins 30 secondes, moins de 95 %, vu dans les 30 derniers jours.
Les entrées sans durée connue, les épisodes seulement prévus et les durées
non finies sont exclus. Aucun nouveau balayage de sources n’est déclenché à
l’affichage de la carte. Le filtre de l’accueil écarte aussi les titres déjà
identifiés comme animés, qui gardent leur reprise dans l’espace Animés.

Une proposition au maximum par profil et processus. Elle ne force pas le
focus et ne lance pas automatiquement la vidéo. Fermeture manuelle ou après
10 secondes sans focus ; aucun délai ne retire le bouton pendant sa sélection.
« Reprendre » appelle le parcours existant qui retrouve une source actuelle,
sans lire directement une URL sauvegardée. Le changement de profil et la
suppression de l’historique retirent la proposition précédente.

## Validation préparée

Les tests de `NTVCoreTests` couvrent les états de sources, la confidentialité
des erreurs, l’isolation/persistance/effacement de l’historique, ses limites,
et l’éligibilité/déduplication de la suggestion. Ils doivent être exécutés sur
la cible tvOS. Le contrôle syntaxique Windows n’est pas une compilation.
Un parcours télécommande dans `NTVDesignSmoke` vérifie aussi la place restante
des affiches, l’accès à « Tout effacer » et le retour du focus au champ. Son
historique de démonstration utilise un domaine de test séparé, jamais celui
du profil réel de l’utilisateur.

Le planning existe séparément dans **Animés → Planning** : sept jours et
horaires locaux de diffusion AniList, sans garantie de disponibilité dans
les addons de l’utilisateur.
