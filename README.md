# aiBank

A fake banking app (SwiftUI, iOS 27.3) built as a **functional core / imperative shell**, with Siri / App Intents support.
Nothing leaves the device: a fake server (JSON over an in-process transport, state persisted to disk) stands in for the bank.

Demo sign-in: card `4500 1234 5678 9010`, password `aibank1`.

## Layout

| Path | Layer | Rules |
|---|---|---|
| `Packages/AIBankKit/Sources/AIBankCore` | Pure core | Foundation only. Domain model (`Money`, `Account`, `ETransferDraft`…), reducers, `BankEffect` values. No I/O, clocks, randomness. |
| `Packages/AIBankKit/Sources/AIBankBoundary` | Boundary | DTOs, DTO ↔ domain parsing, `FakeBankServer` actor, `FakeBackend.client()`. |
| `AIBank/App`, `AIBank/Views` | Shell | `Store` (runs reducer, interprets effects), SwiftUI views, live environment. |
| `AIBank/Intents` | Shell | App Intents: entities, tool intents, App Shortcuts. |
| `AIBank/Skills.skillsbundle` | Siri | Task skills Siri reads (send e-Transfer, pay bill, account questions). |

## Commands

```sh
xcodegen generate                                   # regenerate AIBank.xcodeproj (patches the skillsbundle file type)
(cd Packages/AIBankKit && swift test)               # 46 core + boundary tests
xcodebuild -project AIBank.xcodeproj -scheme AIBank -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test
xcrun sirimetadataanalyzer <path to built aiBank.app>
```
