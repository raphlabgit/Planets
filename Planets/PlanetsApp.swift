//
//  PlanetsApp.swift
//  Planets
//
//  Planets — planètes en orbite les unes autour des autres.
//  Réécriture SwiftUI (iPhone, iPad, Mac) de la version Objective-C de 2008.
//

import SwiftUI

@main
struct PlanetsApp: App {
    init() {
        SimulationSettings.registerDefaults()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .defaultSize(width: 1024, height: 720)
        .commands {
            CommandMenu("Simulation") {
                Button("Réinitialiser l'animation") {
                    NotificationCenter.default.post(name: .planetsReset, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
        #endif

        #if os(macOS)
        Settings {
            PreferencesView(isSheet: false)
        }
        #endif
    }
}
