//
//  SiteRadioApp.swift
//  SiteRadio
//
//  Created by anpoliros on 2025/10/20.
//

import SwiftUI

@main
struct SiteRadioApp: App {
    @StateObject private var appModel = AppModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
        }
    }
}


