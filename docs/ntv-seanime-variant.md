# Variante nTV inspirée de Seanime

Première étape de présentation native sur la branche `ci/ntv-seanime`. La référence antérieure est conservée sur `backup/ntv-before-seanime-2026-10-17`, au commit `c326e186723edde11a4682a0eb4fdac8b6f45b3d`.

## Présentation

- Rail gauche compact, libellés déployés quand la télécommande entre dans le menu. Le panneau se superpose au contenu ; sa largeur ne redimensionne pas les affiches.
- Fonds charbon, surfaces sobres et accent lavande discret ; logo nTV conservé.
- Accueil avec affiche portrait, titre, métadonnées, résumé et action existante. Les recommandations restent exclusivement issues de XPERIENCE ; aucun catalogue d’addon n’est ajouté par la variante.
- Films et séries : même modèle de catalogues, résumé avec affiche et panneau de catégories borné en hauteur.
- Dans la disposition avec rail gauche, un bouton Catégories explicite en haut du catalogue évite de donner deux destinations au même geste. Haut depuis la première rangée rejoint ce bouton ; gauche au bord rejoint le menu principal. La disposition avec menu supérieur garde son accès latéral aux catégories.
- Fiche de contenu : affiche à gauche, informations et actions existantes à droite. L’affiche d’ouverture reste fixe lorsque les métadonnées sont enrichies.
- Planning Animés : deux colonnes lisibles, heures locales et disponibilité distincte de la diffusion. L’API et la sélection des sources restent identiques.

Cette présentation adapte le thème `nTV — Nuit` existant. Les autres palettes et les préférences d’apparence enregistrées ne sont pas réinitialisées.

## Retour à la référence et données

La sauvegarde locale complète contient une archive des 785 fichiers suivis et un bundle d’historique. Le bundle a été vérifié et cloné ; l’arbre restauré correspond exactement à la référence.

Avant de revenir à la branche de référence, sauvegarder ou committer les modifications en cours, puis sélectionner cette branche. Ne pas employer de réinitialisation destructive.

La position du menu Seanime est une préférence locale séparée par profil, sous `ntv.seanime.navigation.v1.p<ID>`. Elle démarre à gauche. Le réglage Position du menu fonctionne toujours. La valeur de l’interface précédente dans `orivio.homecatalog.v1` est conservée et les réglages Seanime ne sont pas ajoutés à la synchronisation du compte.

Les moteurs de lecture, profils, identifiants, addons, historique et URLs de flux ne sont pas migrés ou remplacés par cette présentation. La sauvegarde du lecteur avant Nuvio et le paquet de retour de la version 38 restent séparés.

## Vérification

Les tests préparés vérifient l’isolation des préférences, le maintien des illustrations lors de l’enrichissement et les dimensions du rail avec la vraie télécommande du simulateur. Le parcours `testSeanimeRailFitsAndKeepsHomeGeometryStableWhenExpanded` capture l’accueil, le menu ouvert et le retour au contenu. Les parcours existants continuent de couvrir recherche, catégories, lecture et sous-titres.

Les contrôles de syntaxe et de secrets sur Windows ne prouvent ni la compilation SwiftUI ni les performances tvOS. Les tests et captures natives de cette variante attendent la remise en service de GitHub Actions. Aucun nouveau résultat FPS ni paquet installé n’est revendiqué.

Le changement de matière du rail et des catégories suit la direction graphique demandée. Aucun mode de performance n’est imposé ; les options existantes de lecture et d’effets restent disponibles.

Les nouvelles affiches du résumé et de la fiche transmettent leur hauteur en points au cache d’images existant. Celui-ci calcule déjà la densité de l’écran et une marge de qualité : la variante évite un double suréchantillonnage inutile, sans réduire la définition demandée à l’affichage.

L’animation d’élargissement reste portée par le rail lui-même. La transaction d’animation de focus à la racine n’est plus propagée à toutes les affiches et au résumé pour cette disposition. Ce changement de portée ne constitue pas une mesure de gain FPS.
