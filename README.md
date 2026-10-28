# Planets (Swift)

Réécriture en SwiftUI de **Planets**, le simulateur de planètes en orbite écrit en Objective-C / Cocoa en 2008
(versions 0.93 et 0.94). Une seule base de code pour **iPhone, iPad et Mac**.

## Ouvrir et lancer

1. Ouvrir `Planets.xcodeproj` avec **Xcode 16 ou plus récent**.
2. Dans *Signing & Capabilities*, choisir son équipe (Team) pour la signature.
3. Choisir la destination (un iPhone, un iPad, ou « My Mac ») puis ⌘R.

Cibles minimales : iOS / iPadOS 17, macOS 14.

## Fonctionnement

- Au lancement, un nombre défini de planètes est placé au hasard, chacune avec sa taille, sa masse
  (proportionnelle à la surface, donc définie par la taille) et un vecteur vitesse.
- Chaque planète est attirée par toutes les autres (gravitation de Newton).
- Lors d'un choc, la plus grosse absorbe la plus petite et grandit (masse et quantité de mouvement conservées).
- Au-delà de la **taille critique**, la planète explose en fragments plus petits, chacun avec sa taille,
  sa vitesse et sa direction.
- Un **clic / toucher** dans l'espace fait apparaître un **trou noir** : il attire et absorbe les planètes
  qui franchissent son horizon, tourne de plus en plus vite, puis s'évanouit à la fin de sa durée de vie.
- S'il ne reste qu'une planète, elle explose ; s'il n'en reste aucune, une nouvelle série démarre
  (comme dans la version d'origine).
- Plein écran sur iPhone ; fenêtre redimensionnable sur iPad (Split View, Stage Manager) et sur Mac.

## Préférences (bouton ⚙︎, ou ⌘, sur Mac)

| Réglage | Défaut |
| --- | --- |
| Nombre de planètes au lancement | 100 |
| Taille minimale / maximale des planètes | 4 / 10 px |
| Vitesse initiale max. | 40 px/s |
| Gravité | × 1 |
| Taille critique avant explosion | 40 px |
| Puissance des explosions | 120 px/s |
| Bords de la fenêtre | Traverser (ou Rebondir) |
| Durée de vie du trou noir | 10 s |
| Taille / force du trou noir | 60 px / × 1 |
| Fond étoilé, couleur selon la taille, vecteurs vitesse | oui / oui / non |

Bouton **Réinitialiser l'animation** dans les préférences (et ⌘R sur Mac). Le bouton ⏸ met la simulation en pause.

## Organisation du code

| Fichier | Rôle | Équivalent Objective-C |
| --- | --- | --- |
| `PlanetsApp.swift` | Point d'entrée, fenêtre, menu Mac | `main.m`, `MainMenu.xib` |
| `ContentView.swift` | Fond, boutons, clic → trou noir | `Espace` (`mouseDown:`) |
| `SpaceView.swift` | Dessin des planètes et trous noirs | `Espace` (`drawRect:`), `Planete draw:`, `TrouNoir draw:` |
| `Simulation.swift` | Gravité, chocs, explosions, trous noirs | `AppController calcul:`, `PlaneteArray` |
| `Bodies.swift` | Structures `Planet` et `BlackHole` | `Planete`, `TrouNoir` |
| `SimulationSettings.swift` | Préférences enregistrées | constantes de `Planets_Prefix.pch` |
| `PreferencesView.swift` | Écran des préférences | curseurs G / masse de `MainMenu.xib` |
| `Vec2.swift` | Calcul vectoriel | `sommeVecteur:`, `multiplieVecteur:`… |

L'icône d'origine est reprise dans `Assets.xcassets`, avec les nouvelles images du fond (`fond.png`) et du trou noir (`blackhole.png`).
