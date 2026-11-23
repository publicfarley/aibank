import AIBankBoundary
import AIBankCore
import SwiftUI

struct SignInView: View {
    let store: AppStore
    @FocusState private var focus: Field?
    private enum Field { case card, password }

    private var session: SessionState { store.state.session }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header

                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Card number").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                        TextField("0000 0000 0000 0000", text: Binding(
                            get: { session.cardText },
                            set: { store.send(.signIn(.cardTextChanged($0))) }))
                            .keyboardType(.numberPad)
                            .textContentType(.creditCardNumber)
                            .focused($focus, equals: .card)
                            .fieldStyle()
                            .accessibilityIdentifier("cardNumberField")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Password").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                        SecureField("Password", text: Binding(
                            get: { session.password },
                            set: { store.send(.signIn(.passwordChanged($0))) }))
                            .textContentType(.password)
                            .focused($focus, equals: .password)
                            .submitLabel(.go)
                            .onSubmit(submit)
                            .fieldStyle()
                            .accessibilityIdentifier("passwordField")
                    }
                }

                if let message = session.errorMessage { ErrorBanner(message: message) }

                Button(action: submit) {
                    if session.isSubmitting { ProgressView().tint(.white) } else { Text("Sign In") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(session.isSubmitting)
                .accessibilityIdentifier("signInButton")

                demoHint
            }
            .padding(24)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.canvas)
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "building.columns.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .accessibilityHidden(true)
            Text("aiBank").font(.largeTitle.bold())
            Text("Sign in to your accounts").foregroundStyle(.secondary)
        }
        .padding(.top, 48)
    }

    private var demoHint: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Label("Demo bank", systemImage: "info.circle").font(.subheadline.weight(.semibold))
                Text("This is a pretend bank. Nothing leaves your device.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Card \(CardNumber(FakeBackend.demoCardNumber)?.spaced ?? "")\nPassword \(FakeBackend.demoPassword)")
                    .font(.footnote.monospaced())
                Button("Fill in demo credentials") {
                    store.send(.signIn(.cardTextChanged(FakeBackend.demoCardNumber)))
                    store.send(.signIn(.passwordChanged(FakeBackend.demoPassword)))
                    focus = nil
                }
                .font(.footnote.weight(.semibold))
                .accessibilityIdentifier("fillDemoButton")
            }
        }
    }

    private func submit() {
        focus = nil
        store.send(.signIn(.submitTapped(now: .now)))
    }
}

private extension View {
    func fieldStyle() -> some View {
        self
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
