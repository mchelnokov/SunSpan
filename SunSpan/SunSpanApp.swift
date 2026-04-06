// Copyright (c) 2026 SunSpan Contributors. MIT License — see LICENSE file.

import SwiftUI

@main
struct SunSpanApp: App {
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()

                if showSplash {
                    SplashView()
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeOut(duration: 0.5)) {
                        showSplash = false
                    }
                }
            }
        }
    }
}

struct SplashView: View {
    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            Image(isLandscape ? "SplashLandscape" : "SplashPortrait")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
        }
    }
}
