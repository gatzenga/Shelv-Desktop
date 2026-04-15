import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selection: SidebarItem?
    @Environment(\.themeColor) private var themeColor

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SidebarItem.allCases, id: \.self) { item in
                SidebarRow(
                    item: item,
                    isSelected: selection == item,
                    themeColor: themeColor
                ) {
                    selection = item
                }
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 290)
    }
}

// MARK: - Sidebar Row

struct SidebarRow: View {
    let item: SidebarItem
    let isSelected: Bool
    let themeColor: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Label(LocalizedStringKey(item.rawValue), systemImage: item.icon)
                .font(.body)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? themeColor : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            isSelected
                                ? themeColor.opacity(0.15)
                                : isHovered
                                    ? Color.primary.opacity(0.06)
                                    : Color.clear
                        )
                }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

#Preview {
    SidebarView(selection: .constant(.discover))
        .environmentObject(AppState.shared)
        .frame(width: 200, height: 400)
}
