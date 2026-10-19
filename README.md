# Biathlon Live

App iOS gratuite de suivi de la Coupe du monde de biathlon : course en direct, calendrier, résultats, classements et favoris.

## Lancer le projet

```sh
brew install xcodegen
xcodegen          # génère Biathlon.xcodeproj à partir de project.yml
open Biathlon.xcodeproj
```

Renseigner `DEVELOPMENT_TEAM` dans `project.yml` avant de lancer sur un appareil.

Tests du client API (sans Xcode) :

```sh
cd Packages/BiathlonKit && swift test
```

## Structure

- `Packages/BiathlonKit` : modèles et client de l'API biathlonresults.com, testés avec Swift Testing.
- `App` : l'app SwiftUI (iOS 26, Swift 6, isolation `MainActor` par défaut, Observation, SwiftData pour les favoris).
- `server` (à venir) : Cloudflare Worker qui sert de cache et envoie les notifications d'annulation et de décalage.

## Données

Données issues de l'IBU Datacenter (biathlonresults.com). L'API n'est pas documentée officiellement ; voir `docs/etape1-faisabilite.md`.
