# nTV — première étape visuelle

Le nom public est **nTV**. Un mot-symbole provisoire est utilisé dans l’interface
en attendant le logo fourni. Les noms de targets Xcode, clés de stockage, URL de
connexion et identifiants des services upstream restent stables.

Le code personnalisé est dans `OrivioTV/Custom/DesignSystem` : palette bleu nuit,
texte clair, accent bleu, arrondis et contrôles avec focus visible. La nouvelle
palette est proposée par le sélecteur existant et devient le défaut d’une nouvelle
installation. Les préférences déjà enregistrées par profil restent prioritaires.

La navigation par défaut est un rail latéral à gauche : compact dans le contenu,
avec des libellés quand le focus entre dans le menu. Ce choix reprend la qualité
de disposition appréciée dans SWIPTV, avec une identité nTV propre. Le rail est
opaque et sobre ; il conserve les destinations et callbacks existants. Films,
Séries, Addons et Twitch seront raccordés lors des étapes suivantes. Les
préférences de navigation déjà enregistrées restent prioritaires. Le focus actif reçoit une bordure bleue,
y compris lorsque les animations/parallaxes sont désactivées. Les nouveaux boutons
réutilisent les garde-fous de mouvement et de performance upstream.

Les affiches proviennent de `MetaItem.poster` et passent par `RemoteImage`, avec
le cache et le redimensionnement existants. Aucun catalogue ni visuel de film
de démonstration n’est injecté dans la production. Si une affiche manque, la carte
affiche le titre et une icône. La compatibilité réelle XPERIENCE sera vérifiée avec
son manifest configuré, lors de l’intégration des addons.

La CI compile Release pour l’Apple TV et Debug pour le simulateur, puis exécute
`NTVDesignSmoke` sur le simulateur. Le test vérifie le nom, l’accès à Bibliothèque
avec la télécommande et le retour du focus sur sa destination. Il ne certifie pas
la lecture, les performances ni toutes les interactions sur une Apple TV physique.

Générer le projet depuis `project.yml` avec XcodeGen avant un build local : le
workflow le fait à chaque run pour inclure les nouveaux fichiers Custom.
