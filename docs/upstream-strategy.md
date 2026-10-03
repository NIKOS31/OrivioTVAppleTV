# Orivio TV Custom — socle Git et compilation

Notre fork : https://github.com/NIKOS31/OrivioTVAppleTV

Projet upstream : https://github.com/prehakanson-art/OrivioTVAppleTV

Révision auditée : `0c30f52ea611f5dee9f08f4e64e3655c5bd13a09` (`v0.11`).

## Organisation Git

Le clone conserve l'historique upstream. `origin` pointe vers notre fork et
`upstream` vers le projet original ; les pushes par défaut vont vers `origin`.
Cette première étape est isolée sur `ci/tvos-baseline` et ne modifie aucun moteur.

```sh
git remote add upstream https://github.com/prehakanson-art/OrivioTVAppleTV.git
git config remote.pushDefault origin
```

Créer une branche par changement, puis une PR vers le `main` de notre fork.
Conserver les services et view models existants ; ajouter les futures vues,
composants et services Twitch dans `OrivioTV/Custom`.

Pour synchroniser ultérieurement, partir d'un `main` propre et à jour :

```sh
git fetch origin
git fetch upstream --tags
git switch -c sync/upstream origin/main
git merge --no-ff upstream/main
```

En cas de conflit, relever les fichiers avec `git diff --name-only --diff-filter=U`
et les SHA des deux branches. Résoudre et vérifier chaque conflit, ou abandonner
la fusion avec `git merge --abort`. Ne pas effectuer de reset/force push ni de
résolution générale qui remplace tous les fichiers par un seul côté.

Ouvrir ensuite une PR de synchronisation. Aucun merge ou release automatique n'est
prévu à cette phase ; l'automatisation de sync viendra après les validations.

## Compiler sans Mac personnel

Le workflow **tvOS baseline** utilise `macos-26`, Xcode **26.6** et XcodeGen
**2.46.0**. Les actions sont verrouillées sur leur SHA, le téléchargement de
XcodeGen est vérifié par SHA-256, et les révisions SwiftPM upstream sont conservées.

Le workflow tourne sur `main`, les branches `ci/**`, les PR vers `main`, ou à la
demande depuis Actions → tvOS baseline → Run workflow lorsqu'il est dans la branche
principale. GitHub peut demander d'activer Actions sur un nouveau fork.

Il copie `Secrets.example.swift` vers **OrivioTV/Secrets.swift**, puis génère le
projet depuis `project.yml`. Les clés optionnelles restent vides en CI ; aucune
connexion Orivio/Trakt/SIMKL n'est nécessaire à la compilation.

Le script `scripts/ci/build-tvos.sh` prépare le compilateur Metal s'il manque, puis
compile Release pour l'appareil et Debug pour le simulateur, sans signature ni
provisionnement. La configuration de signature
upstream reste inchangée dans les sources : nos identités app/extension/App Group
devront être définies et vérifiées avant une distribution signée.

Le premier run doit être réellement exécuté avant d'annoncer un build validé.
Les logs et bundles `.xcresult` sont conservés sept jours, même en cas d'échec.
Le workflow ne publie pas d'IPA ni de release. Il ne lance pas encore les tours UI
existants et ne certifie pas lecture, HDR, audio, PiP, Top Shelf ou focus matériel.

Sur un Mac équipé des versions indiquées :

```sh
export DEVELOPER_DIR=/Applications/Xcode_26.6.app/Contents/Developer
bash scripts/ci/build-tvos.sh
```

Le dossier `build/ci` est ignoré par Git. Les bundles `.xcresult` sont placés dans
un sous-dossier distinct à chaque exécution pour permettre les relances locales.

Références : [image macOS](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md),
[XcodeGen](https://github.com/yonaskolb/XcodeGen/releases/tag/2.46.0),
[forks GitHub](https://docs.github.com/en/pull-requests/how-tos/work-with-forks/fork-a-repo).
