import SwiftUI

/// Pencil amber, from the AccentColor asset (deeper in light mode, brighter in dark).
extension Color {
    static let pencil = Color.accentColor
}

/// Rounded card used across the main window.
struct Card<Content: View>: View {
    var title: LocalizedStringResource?
    var trailing: LocalizedStringResource?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if title != nil || trailing != nil {
                HStack {
                    if let title { SectionLabel(title) }
                    Spacer()
                    if let trailing {
                        Text(trailing).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.background.secondary))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
    }
}

/// Small uppercase section label, like a card heading.
struct SectionLabel: View {
    let text: LocalizedStringResource
    init(_ text: LocalizedStringResource) { self.text = text }

    var body: some View {
        Text(String(localized: text).uppercased(with: .current))
            .font(.caption.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}

/// A keyboard key, drawn like a keycap.
struct KeyCap: View {
    let label: LocalizedStringResource
    var symbol: String?

    var body: some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol).imageScale(.small) }
            Text(label).lineLimit(1)
        }
        .fixedSize() // a keycap never wraps or squeezes
        .font(.system(.callout, design: .rounded).weight(.medium))
        .padding(.horizontal, 8)
        .frame(minWidth: 30, minHeight: 24)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.background))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 0, x: 0, y: 1)
    }
}

/// Selectable chip, e.g. which hotkeys are active.
struct Chip: View {
    let label: LocalizedStringResource
    var symbol: String?
    var isOn: Bool

    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol) }
            Text(label)
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .foregroundStyle(isOn ? Color.primary : Color.secondary)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(isOn ? Color.pencil.opacity(0.18) : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(isOn ? Color.pencil.opacity(0.8) : Color.secondary.opacity(0.35), lineWidth: 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(isOn ? Text("On") : Text("Off"))
    }
}

/// Small coloured status pill.
struct StatusBadge: View {
    let text: LocalizedStringResource
    let color: Color
    var showsProgress = false

    var body: some View {
        HStack(spacing: 5) {
            if showsProgress {
                ProgressView().controlSize(.mini)
            } else {
                Circle().fill(color).frame(width: 6, height: 6)
            }
            Text(text)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.14)))
    }
}

/// Stat tile for the right-hand column.
struct StatTile<Detail: View>: View {
    let label: LocalizedStringResource
    let value: String
    var unit: LocalizedStringResource?
    var accent = false
    @ViewBuilder var detail: Detail

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(label)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: value)
                    .font(.system(.title, design: .rounded).weight(.semibold)) // supporting figures, not the page's headline
                    .foregroundStyle(accent ? Color.pencil : Color.primary)
                    .contentTransition(.numericText())
                if let unit {
                    Text(unit).font(.callout).foregroundStyle(.secondary)
                }
            }
            detail
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.background.secondary))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }
}

extension StatTile where Detail == EmptyView {
    init(label: LocalizedStringResource, value: String, unit: LocalizedStringResource? = nil, accent: Bool = false) {
        self.init(label: label, value: value, unit: unit, accent: accent) { EmptyView() }
    }
}

/// Five-week activity grid, a column per weekday.
struct ActivityGrid: View {
    let days: [(date: Date, count: Int)]

    var body: some View {
        let peak = max(days.map(\.count).max() ?? 0, 1)
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(14), spacing: 5), count: 7), alignment: .leading, spacing: 5) {
            ForEach(days.indices, id: \.self) { index in
                let count = days[index].count
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .fill(count == 0 ? Color.secondary.opacity(0.15) : Color.pencil.opacity(0.35 + 0.65 * Double(count) / Double(peak)))
                    .frame(width: 14, height: 14)
                    .help(Text("\(days[index].date.formatted(date: .abbreviated, time: .omitted)): \(count) dictations"))
            }
        }
        .frame(width: 7 * 14 + 6 * 5, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Activity over the last five weeks"))
        .accessibilityValue(Text("Dictated on \(days.filter { $0.count > 0 }.count) of \(days.count) days"))
    }
}

/// Orange call-to-action strip shown when setup is incomplete.
struct Banner: View {
    let symbol: String
    let message: LocalizedStringResource
    let actionTitle: LocalizedStringResource
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.orange)
            Text(message).font(.callout)
            Spacer()
            Button(action: action) { Text(actionTitle) }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.orange.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.orange.opacity(0.35), lineWidth: 0.5))
    }
}
