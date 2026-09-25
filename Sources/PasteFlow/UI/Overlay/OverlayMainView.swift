import SwiftUI

public struct OverlayMainView: View {
    @ObservedObject private var appState = AppState.shared
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header Bar
            HStack {
                PinboardTabBar()
                Spacer()
                SearchBarView()
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 10)
            
            Divider()
                .opacity(0.2)
            
            // MARK: - Card Deck
            CardDeckView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 310)
        .background(
            ZStack {
                VisualEffectView(
                    material: .hudWindow,
                    blendingMode: .behindWindow,
                    state: .active
                )
                
                // Subtle top border highlight
                VStack {
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 1)
                    Spacer()
                }
            }
        )
    }
}
