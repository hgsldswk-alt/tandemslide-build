import StoreKit
import SwiftUI

@main
struct TandemSlideApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .tint(D.amber)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $model.tab) {
            WeighView()
                .tabItem { Label("Weigh", systemImage: "scalemass.fill") }
                .tag(Tab.weigh)
            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(Tab.history)
            RigView()
                .tabItem { Label("Rig", systemImage: "truck.box.fill") }
                .tag(Tab.rig)
        }
        .foregroundStyle(D.ink)
        .task { await model.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.now = Date()
                Task { await model.purchases.refresh() }
            }
        }
        .onReceive(model.purchases.objectWillChange) { _ in model.objectWillChange.send() }
        .sheet(item: $model.reweighing) { weigh in
            ReweighSheet(weigh: weigh)
        }
        .sheet(item: $model.share) { share in
            ActivitySheet(items: share.items).presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $model.showPaywall) {
            PaywallView(purchases: model.purchases)
        }
        .overlay {
            if model.showMilestone {
                ZStack(alignment: .bottom) {
                    Color.black.opacity(0.5).ignoresSafeArea()
                        .onTapGesture { model.showMilestone = false }
                    MilestoneView()
                        .background(D.card, in: RoundedRectangle(cornerRadius: 26))
                        .padding(12)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                Text(toast)
                    .font(.footnote.weight(.semibold))
                    .padding(.vertical, 10).padding(.horizontal, 16)
                    .background(D.raised, in: Capsule())
                    .padding(.bottom, 64)
                    .accessibilityIdentifier("toast")
            }
        }
    }
}
