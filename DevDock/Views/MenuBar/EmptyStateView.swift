import SwiftUI

struct EmptyStateView: View {
    var isSearching: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: isSearching ? "magnifyingglass" : "moon.zzz.fill")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
            Text(isSearching ? "No matches" : "No servers running")
                .font(.system(size: 13, weight: .semibold))
            Text(isSearching
                 ? "Try a different project name, framework, or port."
                 : "Start a dev server and it will appear here automatically.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 46)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
    }
}
