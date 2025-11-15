//
//  vpnApp.swift
//  vpn
//
//  Created by apple on 12/10/2025.
//

import SwiftUI

@main
struct vpnApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
