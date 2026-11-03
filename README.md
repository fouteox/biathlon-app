# Biathlon Live

App iOS gratuite de suivi de la Coupe du monde de biathlon : course en direct, calendrier, résultats, classements et favoris.

## Lancer le projet

```sh
open Biathlon.xcodeproj
```

Le projet Xcode est versionné et utilise des dossiers synchronisés : tout fichier ajouté sous `App/` fait partie de l'app, sous `Widgets/` de l'extension des widgets et des Live Activities, sous `Shared/` des deux, sous `BiathlonTests/` des tests de l'app et sous `BiathlonUITests/` de ses tests d'interface, sans modifier `Biathlon.xcodeproj/project.xcproj` (format JSON5 d'Xcode 27.2, lisible avec [xcode-project-format](https://github.com/apple/xcode-project-format)). Les réglages de compilation sont dans `Configs/Project.xcconfig` (communs), `Configs/Biathlon.xcconfig` (cible de l'app) et `Configs/BiathlonWidgets.xcconfig` (extension), `Configs/BiathlonTests.xcconfig` (tests de l'app), `Configs/BiathlonUITests.xcconfig` (tests d'interface), avec `Configs/Info.plist`, `Configs/BiathlonWidgets-Info.plist` et `Configs/Biathlon.entitlements`. Modifier ces fichiers plutôt que les réglages dans l'éditeur de projet d'Xcode.

Tests de `BiathlonKit` (sans Xcode) :

```sh
cd Packages/BiathlonKit && swift test
```

Tests de l'app (cible `BiathlonTests`, Swift Testing, hébergée par l'app) et de `BiathlonKit` sur le simulateur : Product > Test (⌘U) dans Xcode, ou `xcodebuild test -scheme Biathlon -destination 'platform=iOS Simulator,name=<iPhone>'`. Le transport HTTP, App Attest et le centre de notifications y sont remplacés par des doublures : tout se teste sans serveur ni course.

Tests d'interface (cible `BiathlonUITests`, XCTest) dans le même schéma : ils parcourent les listes de l'app et vérifient que VoiceOver lit chaque ligne d'un seul tenant, avec l'audit d'accessibilité de Xcode (`performAccessibilityAudit`). Ils lancent l'app avec `--sample-data` : en Debug, elle lit alors une Coupe du monde fictive placée autour de la date du jour (`IBUClient.sample`, dans BiathlonKit), sans serveur ni réseau. Aucune course n'est nécessaire, et les données de l'IBU ne sont pas recopiées dans le dépôt.

Mise en forme du code Swift (`swift format`, inclus dans la toolchain Swift 6 ; règles dans `.swift-format`) :

```sh
swift format --in-place --recursive App Shared Widgets BiathlonTests BiathlonUITests Packages/BiathlonKit/Package.swift Packages/BiathlonKit/Sources Packages/BiathlonKit/Tests
```

## Android

L'app Android est en cours d'écriture, en Kotlin et Jetpack Compose (Material 3), dans `android/`, un projet Gradle : Android Studio l'ouvre tel quel. Les versions sont réunies dans `android/gradle/libs.versions.toml`.

```sh
cd android && ./gradlew check
```

`check` lance lint (avertissements traités comme des erreurs) et les tests, qui tournent sur la JVM, sans émulateur ni appareil. Le module `kit` est l'équivalent Kotlin de BiathlonKit : modèles et client de l'API IBU (Ktor, kotlinx.serialization), testés avec JUnit sur les mêmes fixtures (`Packages/BiathlonKit/Tests/BiathlonKitTests/Fixtures`, partagées avec le serveur). Le module `app` est l'interface Compose, testée avec Robolectric. Il faut un JDK 17 ou plus récent et le SDK Android (`ANDROID_HOME`, ou `sdk.dir` dans `android/local.properties`). Les textes et leurs traductions (anglais, français, allemand) viennent du String Catalog de l'app iOS (`Shared/Localizable.xcstrings`), que la tâche Gradle `generateCatalogStrings` convertit en ressources Android : `Updated at %@` devient `R.string.updated_at_arg`. L'URL du serveur et le numéro de version viennent de `Configs/Project.xcconfig`, et le lien vers la politique de confidentialité de `Configs/Biathlon.xcconfig`, comme sur iOS. Les tests des écrans tournent sur la Coupe du monde fictive de `kit/src/testFixtures`, portée de `SampleWorldCup.swift`. Les favoris sont gardés sur l'appareil avec Room (équivalent de SwiftData) ; son schéma est versionné dans `android/app/schemas`, pour écrire les migrations des versions suivantes.

## Xcode Cloud

Xcode Cloud compile `Biathlon.xcodeproj` tel quel, sans script. Il numérote lui-même les builds à partir de 1 : n'envoyer les builds TestFlight que par Xcode Cloud, sinon les numéros se chevauchent.

## Environnement Claude Code cloud

Le conteneur cloud est sous Linux : il compile et teste `BiathlonKit`, mais pas l'app SwiftUI, qui demande macOS et Xcode. L'app est compilée et testée par la CI GitHub Actions sur un runner macOS.

Pour avoir Swift dans le conteneur, coller `scripts/cloud-setup.sh` dans le « Setup script » de l'environnement cloud (il a besoin de `download.swift.org` et `keyserver.ubuntu.com` en HTTPS).

## Règles de fusion

La branche `main` est protégée par le ruleset `.github/rulesets/main.json` (à importer dans Settings > Rules > Rulesets) : pas de push direct ni de force-push, pas de suppression, et une PR ne fusionne que si :

- toutes les conversations sont résolues ;
- la CI est verte (`BiathlonKit (Linux)`, `App (iOS Simulator)`, `Swift format`) ;
- le statut `Codex approval` est vert. Il est publié par `.github/workflows/codex-gate.yml` quand le dernier verdict de Codex sur le dernier commit est sans remarque (👍 sur la description de la PR, ou commentaire « Didn't find any major issues » qui cite ce commit), et que chaque fil ouvert par Codex a reçu au moins une réponse.

## Structure

- `Packages/BiathlonKit` : modèles, client de l'API biathlonresults.com et client du serveur (`ServerClient`), testés avec Swift Testing.
- `BiathlonTests` : les tests de l'app (App Attest, Live Activities des favoris, préférences, rappels).
- `BiathlonUITests` : les tests d'interface (lecture des listes par VoiceOver, audit d'accessibilité).
- `App` : l'app SwiftUI (iOS 26, Swift 6, isolation `MainActor` par défaut, Observation, SwiftData pour les favoris).
- `Widgets` : l'extension WidgetKit : le widget « Prochaine course » (écran d'accueil et écran verrouillé) et la Live Activity d'une course sur l'écran verrouillé et dans la Dynamic Island.
- `Shared` : le code et le String Catalog communs à l'app et à l'extension.
- `android` : l'app Android (Kotlin, Jetpack Compose, Material 3) : `kit` (modèles et clients, testés avec JUnit) et `app` (interface, testée avec Robolectric).
- `server` : Cloudflare Worker qui envoie les alertes d'annulation et de départ décalé, met à jour les Live Activities des courses par des canaux de diffusion APNs, et sert de cache à l'API IBU (voir `server/README.md`).

## Données

Données issues de l'IBU Datacenter (biathlonresults.com). L'API n'est pas documentée officiellement ; voir `docs/etape1-faisabilite.md`.
