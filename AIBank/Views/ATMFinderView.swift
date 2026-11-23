import AIBankCore
import MapKit
import SwiftUI

struct ATMFinderView: View {
    let store: AppStore
    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: ATMState.defaultLocation.latitude,
                                                          longitude: ATMState.defaultLocation.longitude),
                           span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)))

    private var atms: ATMState { store.state.atms }

    private var filter: Binding<ATMFilter> {
        Binding(get: { store.state.atms.filter }, set: { store.send(.atms(.filterChanged($0))) })
    }

    private var selection: Binding<ATM.ID?> {
        Binding(get: { store.state.atms.selectedID }, set: { store.send(.atms(.selected($0))) })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                map.frame(height: 300)
                filters
                list
            }
            .background(Theme.canvas)
            .navigationTitle("Find an ATM")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { store.send(.atms(.appeared(now: .now))) }
        .onChange(of: atms.selectedID) { _, id in
            guard let atm = atms.results.first(where: { $0.id == id })?.atm else { return }
            withAnimation { camera = .camera(MapCamera(centerCoordinate: .init(latitude: atm.coordinate.latitude, longitude: atm.coordinate.longitude), distance: 1_800)) }
        }
    }

    private var map: some View {
        Map(position: $camera, selection: selection) {
            Annotation("You", coordinate: .init(latitude: atms.userLocation.latitude, longitude: atms.userLocation.longitude)) {
                Circle().fill(Color.blue).frame(width: 14, height: 14).overlay(Circle().stroke(.white, lineWidth: 3))
            }
            .annotationTitles(.hidden)
            ForEach(atms.results) { r in
                Marker(r.atm.name, systemImage: r.atm.network == .aiBank ? "building.columns.fill" : "banknote.fill",
                       coordinate: .init(latitude: r.atm.coordinate.latitude, longitude: r.atm.coordinate.longitude))
                    .tint(r.isOpen ? Color.accentColor : .gray)
                    .tag(Optional(r.id))
            }
        }
        .mapControls { MapCompass(); MapScaleView() }
        .accessibilityLabel("Map of nearby ATMs")
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Open now", on: atms.filter.onlyOpenNow) { filter.wrappedValue.onlyOpenNow.toggle() }
                chip("Deposits", on: atms.filter.requiredServices.contains(.deposit)) { toggle(.deposit) }
                chip("Accessible", on: atms.filter.requiredServices.contains(.wheelchairAccessible)) { toggle(.wheelchairAccessible) }
                chip("24 hours", on: atms.filter.requiredServices.contains(.open24Hours)) { toggle(.open24Hours) }
                chip("aiBank only", on: atms.filter.network == .aiBank) {
                    filter.wrappedValue.network = atms.filter.network == .aiBank ? nil : .aiBank
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
    }

    private func toggle(_ service: ATMServices) {
        if filter.wrappedValue.requiredServices.contains(service) { filter.wrappedValue.requiredServices.remove(service) }
        else { filter.wrappedValue.requiredServices.insert(service) }
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.medium))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .foregroundStyle(on ? Color.white : Color.primary)
                .background(on ? Color.accentColor : Theme.surface, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder
    private var list: some View {
        switch atms.atms {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let error):
            ContentUnavailableView {
                Label("Couldn't load ATMs", systemImage: "wifi.exclamationmark")
            } description: { Text(error.message) } actions: {
                Button("Try Again") { store.send(.atms(.appeared(now: .now))) }
            }
        case .loaded:
            let results = atms.results
            if results.isEmpty {
                ContentUnavailableView("No ATMs match", systemImage: "mappin.slash",
                                       description: Text("Try turning off a filter."))
            } else {
                List(results) { r in
                    Button { selection.wrappedValue = r.id } label: { ATMRow(result: r, isSelected: atms.selectedID == r.id) }
                        .buttonStyle(.plain)
                        .listRowBackground(atms.selectedID == r.id ? Color.accentColor.opacity(0.1) : Theme.surface)
                        .accessibilityIdentifier("atm-\(r.id.rawValue)")
                }
                .listStyle(.plain)
            }
        }
    }
}

private struct ATMRow: View {
    let result: ATMResult
    let isSelected: Bool

    var body: some View {
        let atm = result.atm
        HStack(alignment: .top, spacing: 12) {
            SymbolBadge(systemName: atm.network == .aiBank ? "building.columns" : "banknote", size: 44)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(atm.name).font(.body.weight(.semibold))
                    Spacer()
                    Text(result.distanceText).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text("\(atm.address), \(atm.city)").font(.footnote).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(result.isOpen ? "Open" : "Closed").font(.caption.weight(.semibold))
                        .foregroundStyle(result.isOpen ? Theme.positive : .red)
                    Text("· \(atm.hoursText)").font(.caption).foregroundStyle(.secondary)
                    Text("· \(atm.network.withdrawalFee.isZero ? "No fee" : "\(atm.network.withdrawalFee.formatted) fee")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if isSelected {
                    Text(atm.services.labels.joined(separator: " · ")).font(.caption).foregroundStyle(Color.accentColor)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
