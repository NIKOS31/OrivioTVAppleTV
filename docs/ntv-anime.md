# Espace Animés

L'espace reprend les principes d'organisation de [Seanime](https://seanime.app/)
dans la navigation et les couleurs nTV existantes : une sélection de saison
avec bannière fixe et affiches, un planning de sept jours et des fiches.
Il ne contient pas de serveur vidéo, de téléchargement automatique ou de
nouveau moteur. Aucun code ni asset Seanime n'est intégré.

Les métadonnées publiques proviennent de [l'API AniList](https://docs.anilist.co/).
Cette première intégration ne demande ni clé API ni connexion à un compte.
Elle transmet seulement l'année/saison ou les limites d'une journée, sans
historique personnel, URL d'addon, identifiant de débrideur ou URL de lecture.

Les semaines commencent lundi et les journées sont calculées dans le fuseau
de l'appareil avec les changements d'heure. Un horaire est une **diffusion
prévue**, pas la garantie d'un fichier, d'une VF/VOSTFR ou d'un flux disponible.
Le bouton d'une fiche ouvre la recherche existante dans les addons. Le titre
n'est pas utilisé pour déduire automatiquement un identifiant de série, une
saison ou un numéro d'épisode d'un autre fournisseur.

## Limites de cette étape

- Sélection de 24 animés par saison et 50 diffusions par jour ; une indication
  signale les résultats supplémentaires. Pas de pagination silencieuse.
- Pas de synchronisation AniList, liste personnelle ou suivi manga.
- Les résumés gardent la langue fournie par AniList. Les balises sont retirées
  comme texte, sans rendu HTML.
- Contenus marqués adultes ou sans classification exclus de cette sélection.
- Pas de contrôle de disponibilité de flux en arrière-plan ; la recherche
  explicite utilise les sources déjà configurées par l'utilisateur.

## Réseau et fluidité

Une requête à la fois, dédoublonnage, annulation avec la vue, délai maximal de
15 secondes et réponse limitée à 1 Mio. Délai minimal de deux secondes entre
requêtes et respect de Retry-After sur 429. Cache mémoire de dix minutes,
borné à dix sélections. Aucun compte, cookie ou jeton dans ces requêtes.
Les images sont limitées au CDN HTTPS AniList et passent par le pipeline
partagé de redimensionnement et de décodage de nTV.

Les cartes sont chargées paresseusement, sans flou par carte. La bannière
ne change pas au déplacement du focus et n'a pas de timer de carrousel.
Les modifications ne démontrent pas un gain d'images par seconde sur une
Apple TV physique : cette comparaison reste à effectuer sur l'appareil.

## Validation

Les requêtes exactes du service ont été exécutées contre l'API publique.
Tests unitaires préparés : fuseau/changement d'heure, limites calendaires,
validation de schéma/URLs, dédoublonnage, backoff et réutilisation du cache.
Parcours natif préparé : saison → planning → fiche → retour au focus →
recherche d'addon. Ces nouveaux tests attendent leur exécution macOS.
