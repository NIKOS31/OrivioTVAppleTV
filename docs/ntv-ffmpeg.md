# FFmpeg 6.1.6 dans nTV

La version du wrapper FFmpegKit et celle du moteur sont distinctes : le tag
6.1.4 (`c32be9bfb628042737ad3ef622e930c5c7b15954`) contient des archives
tvOS annonçant `n6.1.1`. Les scripts CI reconstruisent les sept bibliothèques
Libav/Libsw depuis la release officielle FFmpeg 6.1.6, dans la même branche
ABI, avant de compiler le lecteur. Les modifications locales de KSPlayer
concernant l’arrêt des threads et les ressources graphiques sont conservées.

## Sources et provenance

- Source : <https://ffmpeg.org/releases/ffmpeg-6.1.6.tar.xz>.
- SHA-256 : `d4fcb164028dd3beee5d92c0ac72e46aac6973c75ea12dc14de07bf8f407370a`.
- Signature détachée vérifiée dans une clé publique isolée, fingerprint
  `FCF986EA15E6E293A5644F10B4322F04D67658D8`. La clé publique checked-in
  vient de <https://ffmpeg.org/ffmpeg-devel.asc> ; aucun secret de signature
  n’est utilisé.
- Les en-têtes Vulkan Khronos 1.3.280, nécessaires aux options précédentes,
  sont épinglés par SHA-256. Aucun moteur Vulkan supplémentaire n’est téléchargé.
- `build/ci/ffmpeg/provenance.json` enregistre les cibles et SHA des sept
  archives produites par plateforme. Les licences source et la provenance
  sont incluses dans les ressources de l’app.

Les options proviennent de la configuration du véritable ancien Libavutil,
pas du numéro du paquet. Les bibliothèques annexes FFmpegKit restent à la
révision épinglée. Les contrôles de configure compilent et lient ces archives
de la bonne plateforme, sans utiliser les bibliothèques installées sur le Mac.
Les capacités vidéo matérielle, TLS, AV1, SRT, SMB et Vulkan précédentes sont
contrôlées. Zlib, Metal, CoreImage et AVFoundation sont activés explicitement
quand l'ancien binaire les annonçait : l'isolement des bibliothèques du Mac
ne doit pas retirer ces fonctions SDK auto-détectées. Libavdevice est aussi reconstruit avec les périphériques désactivés
pour éviter de garder une bibliothèque de la vieille release dans ce groupe.

## Validation requise

- Builds AppleTVOS arm64 et simulateur de l’architecture du Mac.
- `av_version_info()` réellement lié égal à `6.1.6`.
- Disponibilité des décodeurs vidéo/audio/sous-titres et conteneurs attendus.
- Décodage H264 réel depuis la fixture locale et déplacement jusqu’à 2 s.
- Décodage audio réel d’un WAV stéréo synthétique de 4 800 échantillons.
- Tests de navigation/lecteur et tests de sécurité déjà présents.
- Paquet appareil exact, checksum, provenance et scan de données privées.

Le build 19 a réussi les deux compilations et 40 tests, zéro échec, avec la
version liée 6.1.6, décodage H264/seek et PCM stéréo confirmés. Les contrôles
supplémentaires de capacités auto-détectées et les ressources de provenance
font l'objet du lot suivant ; sa réussite doit être vérifiée séparément.

Pour construire cette maintenance, utiliser `bash scripts/ci/build-tvos.sh`
sur macOS/Xcode, puis les scripts de tests et de packaging, comme la CI.
Une compilation Xcode directe avec les archives non préparées du wrapper
peut encore lier l'ancien moteur ; les tests de version la rejetteraient.
Un diagnostic unique au lancement indique la version réellement liée,
y compris en Release, sans URL ni donnée de compte.

La préparation des scripts n’est pas une preuve de compilation ou de lecture.
Le compte rendu de chaque build distingue les contrôles réussis, les erreurs
et les tests physiques encore à faire. La TV n’est pas modifiée par cette CI.
Dolby Vision, HDR, audio multicanal et services d’addons exigent encore la
validation matérielle avant d’affirmer leur compatibilité complète.

Cette maintenance traite le FFmpeg du moteur KSPlayer. Elle ne certifie pas
toutes les bibliothèques annexes ni celles internes à VLC ; leur provenance
et leurs avis de sécurité restent distincts. Une version plus récente ne
prouve pas l’absence de toute vulnérabilité.

Sources : [versions officielles](https://ffmpeg.org/download.html),
[correctifs publiés](https://ffmpeg.org/security.html),
[contrat des bibliothèques](https://ffmpeg.org/doxygen/trunk/md_doc_2APIchanges.html).
