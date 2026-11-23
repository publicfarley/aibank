import AIBankCore
import SwiftUI

/// Flat design: solid fills, one accent, no shadows or gradients. Colours adapt to light and dark.
enum Theme {
    static let cardRadius: CGFloat = 16
    static let positive = Color(red: 0.10, green: 0.60, blue: 0.35)
    static let surface = Color(.secondarySystemGroupedBackground)
    static let canvas = Color(.systemGroupedBackground)
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(.white)
            .background(Color.accentColor.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(Color.accentColor)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.2 : 0.12),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct MoneyText: View {
    let money: Money
    var showsSign = false

    var body: some View {
        Text(money.formatted)
            .monospacedDigit()
            .foregroundStyle(showsSign && money.isPositive ? Theme.positive : .primary)
    }
}

struct Avatar: View {
    let initials: String
    var size: CGFloat = 40

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
            .frame(width: size, height: size)
            .foregroundStyle(Color.accentColor)
            .background(Color.accentColor.opacity(0.14), in: Circle())
            .accessibilityHidden(true)
    }
}

struct SymbolBadge: View {
    let systemName: String
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .semibold))
            .frame(width: size, height: size)
            .foregroundStyle(Color.accentColor)
            .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Shows the right thing for each loading state, and the content once it has some.
struct LoadStateView<Value: Equatable & Sendable, Content: View>: View {
    let state: LoadState<Value>
    var retry: () -> Void
    @ViewBuilder var content: (Value) -> Content

    var body: some View {
        switch state {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity, minHeight: 160)
        case .failed(let error):
            ContentUnavailableView {
                Label("Something went wrong", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error.message)
            } actions: {
                Button("Try Again", action: retry).buttonStyle(.borderedProminent)
            }
        case .loaded(let value):
            content(value)
        }
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline)
            .foregroundStyle(.red)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityElement(children: .combine)
    }
}

extension AccountKind {
    var symbolName: String {
        switch self {
        case .chequing: "banknote"
        case .savings: "building.columns"
        case .tfsa: "leaf"
        case .creditCard: "creditcard"
        case .lineOfCredit: "house"
        }
    }
}

extension TransactionCategory {
    var symbolName: String {
        switch self {
        case .groceries: "cart"
        case .dining: "fork.knife"
        case .transport: "tram"
        case .shopping: "bag"
        case .utilities: "bolt"
        case .housing: "house"
        case .health: "cross.case"
        case .entertainment: "film"
        case .income: "arrow.down.circle"
        case .transfers: "arrow.left.arrow.right"
        case .cash: "dollarsign.circle"
        case .fees: "percent"
        case .other: "ellipsis.circle"
        }
    }
}

extension AppTab {
    var symbolName: String {
        switch self {
        case .accounts: "creditcard.fill"
        case .interac: "paperplane.fill"
        case .bills: "doc.text.fill"
        case .atms: "mappin.and.ellipse"
        }
    }
}

extension Date {
    var shortDay: String { formatted(.dateTime.month(.abbreviated).day()) }
}
