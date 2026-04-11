import SwiftUI

struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: backgroundStops,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.blue.opacity(colorScheme == .dark ? 0.22 : 0.14))
                .frame(width: 340, height: 340)
                .blur(radius: 70)
                .offset(x: -120, y: -240)

            Circle()
                .fill(Color.mint.opacity(colorScheme == .dark ? 0.18 : 0.12))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: 150, y: -120)

            Circle()
                .fill(Color.orange.opacity(colorScheme == .dark ? 0.10 : 0.08))
                .frame(width: 260, height: 260)
                .blur(radius: 90)
                .offset(x: 170, y: 320)
        }
        .ignoresSafeArea()
    }

    private var backgroundStops: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.07, green: 0.09, blue: 0.12),
                Color(red: 0.08, green: 0.12, blue: 0.14),
                Color(red: 0.05, green: 0.07, blue: 0.10)
            ]
        }

        return [
            Color(red: 0.96, green: 0.98, blue: 1.00),
            Color(red: 0.95, green: 0.98, blue: 0.97),
            Color(red: 0.98, green: 0.97, blue: 0.94)
        ]
    }
}
