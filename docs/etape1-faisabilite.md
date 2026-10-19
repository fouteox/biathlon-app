# Étape 1 : source de données et serveur (19 octobre 2026)

## Verdict

Faisable. L'API derrière biathlonresults.com couvre tout le périmètre (calendrier, courses, résultats, classements, fiches athlètes) sans clé ni authentification. Deux points restent ouverts : l'autorisation de l'IBU, et le comportement exact du direct, qu'on ne pourra observer qu'à la reprise des courses.

## Ce que l'API fournit (testé le 19/10/2026)

Base : `https://biathlonresults.com/modules/sportapi/api/`

| Besoin | Endpoint | Testé |
|---|---|---|
| Étapes d'une saison | `Events?SeasonId=2627&Level=1` | oui : 11 étapes, Kontiolahti 23–29/11/2026 en premier |
| Courses d'une étape | `Competitions?EventId=BT2627SWRLCP01` | oui : 6 courses, la 1re le 26/11/2026 à 15:15 UTC (individuel hommes) |
| Résultats et départs | `Results?RaceId=…` | oui : rang, dossard, tirs (`0+2 0+2`), temps, écart, relais par relayeur |
| Temps intermédiaires et analyses | `AnalyticResults?RaceId=…&TypeId=…` | oui |
| Liste des classements | `Cups?SeasonId=2526` | oui : général, par discipline, Coupe des nations, IBU Cup, juniors |
| Classement | `CupResults?CupId=BT2526SWRLCP__SMTS` | oui : rang, points, dossard jaune, évolution du rang, date `AsOf` |
| Fiche athlète | `CISBios?IBUId=…` | oui : photo, drapeau, naissance, stats de tir et de ski par saison |
| Historique athlète | `AllResults?IBUId=…` | connu via la librairie Python `biathlon`, non testé ici |

Champs utiles pour le direct et les alertes dans `Competitions` : `StartTime`, `StatusId`/`StatusText`, `ScheduleStatus`, `ResultStatus`, `IsLive`, `HasLiveData`. Il n'y a pas de champ « annulé » ou « décalé » explicite : le serveur doit comparer `StartTime` et le statut d'un relevé à l'autre.

## Risques

1. **Droits d'utilisation.** Les conditions d'utilisation de biathlonworld.com (section 3) interdisent de reproduire ou redistribuer le contenu sans autorisation écrite de l'IBU. L'API n'est pas documentée publiquement. Des sites et outils tiers l'utilisent depuis des années (realbiathlon.com, librairies Python), mais rien ne prouve un accord. Il faut écrire à l'IBU avant la publication, et éviter son logo et ses marques dans l'app (risque de refus Apple, règle 5.2).
2. **Direct non vérifiable avant la saison.** Aucune course n'est en cours en octobre ; on ne peut pas mesurer la fréquence de mise à jour en direct. Première observation possible le 26/11, en même temps que le lancement. Il faudra donc publier une première version solide sur le calendrier, les résultats et les classements, et ajuster le direct sur les premières courses.
3. **API non officielle.** Elle peut changer sans prévenir (c'est déjà arrivé en 2020 avec l'ajout d'un champ). Le serveur intermédiaire limite l'impact : on corrige côté serveur sans nouvelle version de l'app.

## Architecture proposée

- **Serveur** : Cloudflare Workers, gratuit à cette échelle. Une tâche planifiée chaque minute interroge les courses du jour, détecte les changements d'horaire et de statut, et envoie les notifications push via APNs (et plus tard les mises à jour de Live Activity). Il sert aussi de cache pour l'app, ce qui évite de solliciter l'IBU depuis chaque téléphone.
- **App** : Swift 6.4, SwiftUI, Observation, SwiftData pour les favoris, iOS 26 minimum. Le rappel « X minutes avant le départ » est une notification locale planifiée par l'app ; l'annulation et le décalage viennent du serveur.

## Calendrier

La première course de Coupe du monde est le jeudi 26 novembre 2026. Revue Apple à prévoir quelques jours avant, donc l'app doit être soumise vers le 18–20 novembre.
