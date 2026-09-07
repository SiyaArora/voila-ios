//
//  voilaApp.swift
//  voila
//
//  Created by Siya Arora on 6/30/26.
//

import SwiftUI

@main
struct voilaApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                // Warm the remote prompt at launch so it is ready by the time the
                // user picks a photo. Fire and forget: analysis never waits on it.
                .task {
                    await PromptConfig.shared.refresh()
                    print("PROMPT[launch]: \(await PromptConfig.shared.instructions())")
                }
        }
    }
}
