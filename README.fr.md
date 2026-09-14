# XAssistant Mac

[简体中文](README.md) | [繁體中文](README.zh-Hant.md) | [English](README.en.md) | [日本語](README.ja.md) | [Español](README.es.md) | **Français** | [Deutsch](README.de.md)

Outil local pour macOS qui enregistre l’activité du clavier et de la souris et exporte des vidéos animées avec une carte de chaleur 3D.

Adapté des fonctionnalités et des idées de [xuhk/XAssistant](https://github.com/xuhk/XAssistant), réimplémenté nativement en Swift. Cette version macOS est non officielle et n’est pas affiliée à l’auteur original. Aucun code ni élément graphique du projet Windows n’a été copié. Distribué sous [licence MIT](LICENSE).

## Fonctionnalités

- Enregistrement en arrière-plan depuis la barre des menus, statistiques quotidiennes et carte de chaleur du clavier.
- Détection des claviers intégrés et externes, dispositions MacBook et Mac avec pavé numérique, sélection manuelle possible.
- Choix du début et de la fin, avec raccourcis vers le premier enregistrement et l’heure actuelle.
- Export des appuis animés et des cartes cumulatives en MP4 1080p à 30 images/s dans Téléchargements, avec compression automatique des temps morts.
- Inclusion ou exclusion de la souris ; vitesses de 0.5× à 256×, dont 128×.
- Échelle des couleurs dynamique selon le maximum cumulé courant, ou fixe selon le maximum final de la période sélectionnée.
- Affichage de la carte finale pendant cinq secondes avec une rotation lente de la caméra.
- Son synchronisé à chaque appui, timbre distinct par touche physique et choix entre clavier, mécanique, doux ou silencieux.

## Installation

Nécessite **un Mac Apple Silicon et macOS 13 ou ultérieur**. Xcode n’est pas nécessaire pour l’application téléchargée.

- **Téléchargement :** ouvrez la [dernière version](https://github.com/nope-gao/XAssistant-Mac/releases/latest), téléchargez `XAssistant-Mac-arm64.zip`, décompressez-le et placez **XAssistant Mac.app** dans `~/Applications`.
- **Installation ou mise à jour par Terminal :** quittez d’abord l’application, puis exécutez :

```bash
curl -fsSL https://raw.githubusercontent.com/nope-gao/XAssistant-Mac/main/install.sh -o /tmp/xassistant-install.sh && bash /tmp/xassistant-install.sh
```

Le programme télécharge la dernière version, vérifie SHA-256 et contrôle la compatibilité avec l’exigence de signature de l’application installée. Une mise à jour incompatible est arrêtée avant tout remplacement. L’installation se fait dans `~/Applications` sans sudo et conserve les enregistrements. Une version avec le ZIP de l’application doit avoir été publiée ; l’archive Source code générée par GitHub contient les sources, pas l’application.

Le téléchargement v0.4.0 existant utilise une signature ad-hoc et n’est pas notarié par Apple. Si macOS bloque l’ouverture, vérifiez sa provenance puis utilisez **Réglages Système → Confidentialité et sécurité → Ouvrir quand même**. Autorisez ensuite la surveillance de l’entrée.

## Langue de l’interface

Le réglage initial est **Suivre le système**. L’application parcourt la liste ordonnée des langues préférées de macOS et choisit une langue prise en charge : **简体中文, 繁體中文, English, 日本語, Español, Français, Deutsch**. Elle utilise l’anglais si aucune ne correspond. Vous pouvez choisir une langue ou revenir au système en bas de la fenêtre ; le choix est enregistré.

L’interface, les menus, les messages déjà affichés, les dates et nombres, les étiquettes de souris, les noms des touches de fonction et les sous-titres suivent ce choix. Les lettres conservent la disposition physique ANSI. La vidéo garde la langue choisie au début de l’export, durant lequel le changement manuel est désactivé. macOS contrôle la langue de ses propres autorisations et des détails des erreurs système.

## Son de la vidéo

Choisissez **Frappes de clavier** (par défaut), **Mécanique**, **Frappes douces** ou **Silencieux**. Chaque touche physique possède un timbre court et distinct, déclenché uniquement à l’appui et aligné sur la première image montrant cet appui. À grande vitesse, les sons rapprochés se superposent. Exclure la souris exclut aussi ses clics. Les cinq secondes finales restent silencieuses.

Le son est synthétisé localement. Aucun microphone, enregistrement réel du clavier ou fichier sonore externe n’est utilisé. Les vidéos sonores contiennent une piste AAC à 48 kHz ; le mode Silencieux ne crée aucune piste audio.

## Compiler les sources

Xcode Command Line Tools est nécessaire. Le script ne produit qu’une application ARM64 ; la compatibilité n’a pas été vérifiée sur toutes les versions de macOS visées.

Exécutez la première commande uniquement si les outils manquent. Lancez la compilation dans le dossier du projet ; elle vérifie la signature et exécute les tests intégrés. Quittez l’application existante avant l’installation.

```bash
xcode-select --install
bash build.sh
mkdir -p "$HOME/Applications"
ditto "dist/XAssistant Mac.app" "$HOME/Applications/XAssistant Mac.app"
open "$HOME/Applications/XAssistant Mac.app"
```

Par défaut, la compilation locale utilise une signature ad-hoc, sans Developer ID ni notarisation. Remplacer une application peut invalider ses autorisations.

## Utilisation et autorisations

Après le premier lancement, ouvrez **Réglages Système → Confidentialité et sécurité → Surveillance de l’entrée**, autorisez **XAssistant Mac** depuis son emplacement installé, puis quittez et relancez l’application. Utilisez le clavier et la souris et vérifiez que l’heure du dernier enregistrement et les compteurs progressent réellement avant d’exporter.

Recompiler ou remplacer l’application peut invalider l’autorisation. Si elle est activée mais qu’aucune activité n’est enregistrée, quittez l’application et exécutez :

```bash
tccutil reset ListenEvent local.jasongao.xassistantmac
```

Ajoutez de nouveau l’application installée à la surveillance de l’entrée, autorisez-la et relancez-la. Cette commande ne réinitialise que cette autorisation pour cette application.

Sélectionnez la période, la vitesse, la souris, l’échelle de chaleur et le son, puis cliquez sur **Exporter vers Téléchargements**. Une activité sans enregistrement ne peut pas être récupérée.

## Données locales et confidentialité

Les données sont stockées dans `~/Library/Application Support/XAssistantMac/`. L’application ne les téléverse pas et n’inclut aucune télémétrie. Le programme d’installation contacte GitHub pour télécharger les versions.

La lecture animée nécessite les heures d’appui et de relâchement, les identifiants des touches physiques, les informations d’appareil et l’ordre des événements. Les noms d’applications, Bundle ID et durées d’utilisation sont également enregistrés. L’application ne lit pas le texte final des méthodes de saisie, les titres de fenêtres, les adresses web ou les coordonnées de la souris. **L’ordre des touches peut néanmoins révéler le texte saisi. Les enregistrements sont sensibles : ne publiez pas le dossier de données.**

## Limites connues

- Principalement adapté à ANSI. ISO/JIS ne sont pas entièrement pris en charge ; la détection automatique ne couvre pas nécessairement tous les appareils tiers.
- Les touches Fn, multimédias et la saisie sécurisée peuvent ne pas être intégralement enregistrées. Touch ID n’est pas traité comme une touche ordinaire.
- L’identification de l’appareil source peut être limitée avec plusieurs claviers. Les répétitions automatiques lors d’un appui prolongé ne comptent pas comme des appuis distincts.
- Les vidéos sont produites directement avec SceneKit, Metal et AVFoundation ; Blender n’est pas requis.

## Publier une mise à jour (maintenance)

La version v0.4.0 existante est signée ad-hoc. Désactiver puis réactiver le droit peut conserver l’ancienne exigence de signature, laissant un interrupteur actif sans enregistrement. Les prochaines versions **exigent une identité de signature Developer ID Application stable** ; sans certificat, la publication est bloquée.

Configurez les secrets GitHub Actions `SIGNING_CERTIFICATE_BASE64` (P12 encodé en Base64), `SIGNING_CERTIFICATE_PASSWORD` et `SIGNING_IDENTITY`. Ne commitez jamais la clé privée. Le workflow importe le certificat dans un trousseau temporaire puis le supprime. Conservez la même identité pour les mises à jour. La première migration d’ad-hoc vers Developer ID nécessite une nouvelle autorisation, une fois.

Mettez à jour la version et le numéro de build dans `build.sh`, commitez, puis poussez le tag correspondant :

```bash
git tag v0.4.1
git push origin main --tags
```

Les envois sur main vérifient les traductions, le timing des appuis et l’encodage audio/vidéo réel. Les tags publient une version avec ZIP et somme de contrôle après réussite des tests. Utilisez un nouveau numéro pour chaque mise à jour. Vous pouvez aussi exécuter `SIGNING_IDENTITY="Developer ID Application: …" bash package.sh` avec le certificat installé localement, puis joindre `dist/XAssistant-Mac-arm64.zip` et `dist/SHA256SUMS` à la version GitHub.

`ALLOW_ADHOC_PACKAGE=1 bash package.sh` est réservé aux tests locaux, pas aux mises à jour censées conserver les autorisations. Un chemin et un Bundle ID fixes ne corrigent pas les changements de signature ad-hoc. Consultez les [explications d’Apple sur les exigences de signature et les autorisations](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).
