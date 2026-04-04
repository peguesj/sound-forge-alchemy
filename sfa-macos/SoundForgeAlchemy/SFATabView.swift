import SwiftUI
import AppKit

// MARK: - SFA Tab definition

enum SFATab: String, CaseIterable {
    case library   = "library"
    case dj        = "dj"
    case daw       = "daw"
    case analysis  = "analysis"
    case settings  = "settings"

    var label: String {
        switch self {
        case .library:  return "Library"
        case .dj:       return "DJ"
        case .daw:      return "DAW"
        case .analysis: return "Analysis"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .library:  return "books.vertical.fill"
        case .dj:       return "headphones"
        case .daw:      return "pianokeys"
        case .analysis: return "waveform.badge.magnifyingglass"
        case .settings: return "gearshape.fill"
        }
    }

    // URL hash / path for Phoenix LiveView routing
    var urlTarget: String {
        switch self {
        case .library:  return "#library"
        case .dj:       return "#dj"
        case .daw:      return "#daw"
        case .analysis: return "#analysis"
        case .settings: return "/settings"
        }
    }

    // JS to navigate Phoenix LiveView to this tab
    var navigationJS: String {
        switch self {
        case .settings:
            return "window.location.href = 'http://127.0.0.1:4000/settings';"
        default:
            return """
            (function() {
                var tab = document.querySelector('[data-tab=\"\(rawValue)\"]');
                if (tab) { tab.click(); return; }
                window.location.hash = '\(urlTarget)';
            })();
            """
        }
    }
}

// MARK: - SFA Vertical Tab Strip

struct SFATabStrip: View {
    @Binding var selectedTab: SFATab
    let onSelect: (SFATab) -> Void

    // SFA dark palette
    private static let bgColor   = Color(red: 0.05, green: 0.05, blue: 0.09)
    private static let accentColor = Color(red: 0.55, green: 0.2, blue: 0.9)
    private static let dimColor  = Color.white.opacity(0.35)
    private static let activeColor = Color.white

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            // App logo area
            VStack(spacing: 4) {
                Image(systemName: "waveform")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Self.accentColor)
                    .padding(.top, 16)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 16)

            Divider()
                .background(Color.white.opacity(0.08))
                .padding(.bottom, 8)

            // Tab buttons
            ForEach(SFATab.allCases, id: \.rawValue) { tab in
                SFATabButton(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    accentColor: Self.accentColor,
                    activeColor: Self.activeColor,
                    dimColor: Self.dimColor
                ) {
                    selectedTab = tab
                    onSelect(tab)
                }
            }

            Spacer()
        }
        .frame(width: 64)
        .background(Self.bgColor)
    }
}

// MARK: - Individual tab button

struct SFATabButton: View {
    let tab: SFATab
    let isSelected: Bool
    let accentColor: Color
    let activeColor: Color
    let dimColor: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    // Active indicator pill
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(accentColor.opacity(0.18))
                            .frame(width: 44, height: 44)
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.06))
                            .frame(width: 44, height: 44)
                    }

                    Image(systemName: tab.icon)
                        .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? accentColor : (isHovered ? activeColor : dimColor))
                        .symbolEffect(.bounce, value: isSelected)
                }

                Text(tab.label)
                    .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? accentColor : dimColor)
                    .lineLimit(1)
            }
            .frame(width: 64, height: 60)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .accessibilityLabel(tab.label)
        .accessibilityHint(isSelected ? "Selected tab" : "Tap to switch to \(tab.label)")
    }
}
