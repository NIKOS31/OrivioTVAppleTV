# Focus et performances — état du 16 octobre 2026

La référence physique reste le build 38 : l'utilisateur rapporte environ
48–50 callbacks UI par seconde sur une sortie à 60 Hz. Aucun gain ultérieur
mesuré sur l'appareil n'est revendiqué. Le compteur CADisplayLink indique la
cadence du thread principal, pas les images effectivement présentées par GPU.

## Défauts de code et corrections locales

- L'ancien transfert de rangée lançait une tâche de relance sans propriétaire
  et ignorait l'annulation du sommeil. Une ancienne destination pouvait
  reprendre le focus après un mouvement suivant. Le routeur possède désormais
  une seule tâche et une génération ; changement de rangée, retrait de la
  vue, ouverture du menu ou changement d'onglet annulent la relance.
- La normalisation d'entrée de rangée ne passe plus par un bloc asynchrone
  indépendant qui pouvait sauter au premier élément après le geste suivant.
  L'affectation immédiate et les reprises nécessaires au montage paresseux
  passent par le même routeur annulable.
- Le fond regroupe les changements lors d'un balayage rapide (intervalles
  inférieurs à 140 ms, attente de stabilisation de 180 ms au minimum). Les
  pas isolés conservent le délai habituel et les appareils modestes gardent
  leur délai existant s'il est supérieur. Aucun effet n'est supprimé.
- Les identités de catalogues immuables ne sont plus recomposées à chaque
  accès ; le calcul du hash était déjà en cache, ce n'est donc pas présenté
  comme la suppression d'un hash systématique.
- Les dates de sortie analysées sont mises en cache avec des bornes. Le test
  de sortie reste comparé à l'heure courante, sans cache d'un résultat périmé.
- La liste visible d'une rangée est dérivée une fois par passage de body ;
  le filtre anime garde ses normalisations et empreintes en cache borné.

## Vérification à effectuer

Les tests unitaires et les parcours télécommande sont ajoutés aux sources,
mais n'ont pas encore été exécutés sur macOS pour ce lot local. La vérification
syntaxique sous Windows ne remplace ni la compilation ni ces parcours.

À comparer avec les mêmes réglages visuels et la même fréquence :

1. Déplacements horizontaux continus puis pause sur une affiche.
2. Depuis une colonne éloignée, Bas/Haut/Bas rapides entre trois rangées.
3. Retour d'une fiche vers son affiche ; catégories seulement au bord gauche.
4. Cadence, pire intervalle et retards UI ; mémoire/CPU avec Instruments si
   les symptômes persistent. Le simulateur ne prouve pas la fluidité de la TV.

Tout retrait d'effet ou de fonction pour gagner du temps de rendu requiert
l'accord préalable de l'utilisateur. Les changements de ce lot préservent
les effets et les moteurs existants.
