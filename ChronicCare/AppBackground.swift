import SwiftUI

/// Flat system background — matches Settings / Health / Fitness. Visual safety
/// for a medical app comes from restraint and whitespace, not gradients or
/// blur orbs. High-contrast trait is handled by the system color.
struct AppBackground: View {
    var body: some View {
        EditorialPalette.background
            .ignoresSafeArea()
    }
}
