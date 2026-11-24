import StoreKit
import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("History").font(.largeTitle.weight(.heavy))
                calibrationCard
                let weighs = model.library.weighs(for: model.rig)
                if weighs.isEmpty {
                    Text("Each time you tap “Log re-weigh”, the advice and the second ticket are saved here.")
                        .font(.subheadline).foregroundStyle(D.muted).panel()
                }
                ForEach(weighs) { w in
                    row(w)
                        .contextMenu {
                            Button("Delete", role: .destructive) { model.deleteWeigh(w.id) }
                        }
                }
                if !weighs.isEmpty {
                    Button("Export CSV") { model.exportCSV() }
                        .buttonStyle(BigButton(filled: false))
                        .accessibilityIdentifier("history.csv")
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
        .background(D.bg.ignoresSafeArea())
    }

    private var calibrationCard: some View {
        let c = model.calibration
        return VStack(alignment: .leading, spacing: 4) {
            Text("YOUR TRAILER").font(.caption.weight(.bold)).foregroundStyle(D.muted)
            if c.samples > 0 && model.hasPro {
                Text("\(Int(c.rates.perHole.rounded())) lb / hole").font(.system(size: 34, weight: .heavy)).foregroundStyle(D.green)
                Text("Calibrated from \(c.samples) re-weigh\(c.samples == 1 ? "" : "s")\(c.error.map { " · error about ±\(Int($0)) lb" } ?? "")\n(default was \(Int(model.rig.rates.perHole)) lb/hole)")
                    .font(.subheadline).foregroundStyle(D.muted)
            } else if c.samples > 0 {
                Text("\(c.samples) re-weigh\(c.samples == 1 ? "" : "s") logged").font(.title2.weight(.heavy))
                Button("Unlock calibration") { model.showPaywall = true }.font(.subheadline.weight(.bold)).foregroundStyle(D.amber)
            } else {
                Text("\(Int(model.rig.rates.perHole)) lb / hole (default)").font(.title2.weight(.heavy))
                Text("Log a re-weigh after you slide — the app learns your trailer.").font(.subheadline).foregroundStyle(D.muted)
            }
        }
        .panel(stroke: c.samples > 0 ? D.green : D.line)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("history.calibration")
    }

    private func row(_ w: Weigh) -> some View {
        let legal = w.after.map { model.rig.limits.isLegal($0) }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(w.date.formatted(.dateTime.month(.abbreviated).day()))\(w.place.isEmpty ? "" : " · " + w.place)").font(.headline)
                Spacer()
                if let legal {
                    Text(legal ? "Legal" : "Re-scaled")
                        .font(.caption.weight(.bold)).foregroundStyle(.black)
                        .padding(.vertical, 3).padding(.horizontal, 8)
                        .background(legal ? D.green : D.amber, in: Capsule())
                }
            }
            Text("Advice: \(AdviceCard.headline(w.moved).replacingOccurrences(of: "\n", with: " "))").font(.subheadline).foregroundStyle(D.muted)
            if let p = w.predicted, let a = w.after {
                Text("Predicted drive \(model.unit.format(p.drive)) · actual \(model.unit.format(a.drive))")
                    .font(.subheadline).foregroundStyle(D.muted)
            } else if w.after == nil {
                Button("Add re-weigh") { model.reweighing = w }.font(.subheadline.weight(.bold)).foregroundStyle(D.amber)
            }
        }
        .panel()
    }
}

struct RigView: View {
    @EnvironmentObject private var model: AppModel
    @State private var kpraOn = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Tractor / trailer") {
                    TextField("Tractor", text: bind(\.tractor))
                    TextField("Trailer", text: bind(\.trailer)).accessibilityIdentifier("rig.trailer")
                    Button("Add another tractor/trailer") { model.addRig() }
                }
                Section {
                    Picker("Units", selection: Binding(get: { model.library.unit }, set: { model.library.unit = $0 })) {
                        ForEach(WeightUnit.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Limits", selection: bind(\.preset)) {
                        ForEach(LimitPreset.allCases) { Text($0.title).tag($0) }
                    }
                    if model.rig.preset == .custom {
                        limitField("Steer limit", \.steer)
                        limitField("Drive limit", \.drive)
                        limitField("Trailer limit", \.trailer)
                        limitField("Gross limit", \.gross)
                    }
                } header: { Text("Limits") } footer: {
                    Text("Canada and state limits vary — check your permit and local rules.")
                }
                Section {
                    Stepper("\(Int(model.rig.rates.perHole)) lb per hole", value: bind(\.rates.perHole), in: 50...800, step: 10)
                    Stepper("\(Int(model.rig.rates.perNotch)) lb per fifth-wheel notch", value: bind(\.rates.perNotch), in: 100...1_500, step: 25)
                    Stepper("Holes are \(model.rig.holeSpacing)″ apart", value: bind(\.holeSpacing), in: 1...24)
                } header: { Text("Starting estimate") } footer: {
                    Text("Common: ~250 lb per hole on 6″ spacing. After a few logged re-weighs the app uses your trailer's real numbers.")
                }
                Section {
                    Toggle("Warn before KPRA limit", isOn: Binding(get: { model.rig.rearRoom != nil }, set: { on in
                        if on && !model.hasPro { model.showPaywall = true; return }
                        model.updateRig { $0.rearRoom = on ? 4 : nil }
                    }))
                    if let room = model.rig.rearRoom {
                        Stepper("Holes left toward the rear: \(room)", value: Binding(get: { room }, set: { v in model.updateRig { $0.rearRoom = v } }), in: 0...30)
                    }
                } header: { Text("KPRA (e.g. California 40 ft)") } footer: {
                    Text("Count how many holes you can still slide toward the rear before the kingpin-to-rear-axle distance is over the limit.")
                }
                Section("Share with your fleet") {
                    Button("Copy trailer code") { model.copyTrailerCode() }
                    Button("Paste trailer code") {
                        if model.testing, let text = ProcessInfo.processInfo.environment["UITEST_CODE"] {
                            model.importTrailerCode(text)
                        } else {
                            model.importTrailerCode(UIPasteboard.general.string)
                        }
                    }
                    .accessibilityIdentifier("rig.paste")
                }
                Section {
                    if model.purchases.entitlement?.purchasedPro == true {
                        Label("Unlocked — thank you!", systemImage: "checkmark.seal.fill").foregroundStyle(D.green)
                    } else {
                        Button(model.hasPro ? "Trial: \(model.purchases.entitlement?.trialDaysLeft(at: model.now) ?? 30) days left · Unlock" : "Unlock all features") {
                            model.showPaywall = true
                        }
                        .accessibilityIdentifier("rig.unlock")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(D.bg.ignoresSafeArea())
            .navigationTitle(model.rig.name)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func bind<T>(_ path: WritableKeyPath<Rig, T>) -> Binding<T> {
        Binding(get: { model.rig[keyPath: path] }, set: { v in model.updateRig { $0[keyPath: path] = v } })
    }

    private func limitField(_ title: String, _ path: WritableKeyPath<Limits, Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("lb", value: Binding(get: { model.unit.show(model.rig.custom[keyPath: path]).rounded() },
                                           set: { v in model.updateRig { $0.custom[keyPath: path] = model.unit.store(v) } }),
                      format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 110)
        }
    }
}

struct ShareCard: View {
    let advice: Advice
    let unit: WeightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 24, weight: .heavy)).foregroundStyle(D.ink)
            TruckDiagram(move: advice.move)
            if let p = advice.predicted {
                Text("Steer \(unit.format(p.steer)) · Drive \(unit.format(p.drive)) · Trailer \(unit.format(p.trailer)) \(unit.rawValue)")
                    .font(.subheadline).foregroundStyle(D.muted)
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("#TruckerTips #SlideYourTandems").font(.subheadline.weight(.bold)).foregroundStyle(D.amber)
                    Text("Tandem Slide Calc").font(.caption).foregroundStyle(D.muted)
                }
                Spacer()
                if let qr = QR.image() {
                    Image(uiImage: qr).interpolation(.none).resizable().frame(width: 72, height: 72)
                        .padding(4).background(Color.white, in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(D.bg)
    }

    private var title: String {
        switch advice {
        case .legal: "Already legal — no slide needed"
        case .unload: "Over gross — unload needed"
        case .move(let m, _): AdviceCard.headline(m).replacingOccurrences(of: "\n", with: " ") + " → all legal"
        case .bestEffort(let m, _): AdviceCard.headline(m).replacingOccurrences(of: "\n", with: " ")
        }
    }

    @MainActor
    static func render(advice: Advice, unit: WeightUnit) -> UIImage {
        let renderer = ImageRenderer(content: ShareCard(advice: advice, unit: unit))
        renderer.scale = 3
        return renderer.uiImage ?? UIImage()
    }
}

struct MilestoneView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            Text("MILESTONE").font(.caption.weight(.bold)).foregroundStyle(D.muted)
            Text("\(model.library.milestones.firstTryLegal) legal on the first re-weigh").font(.title.weight(.heavy))
                .multilineTextAlignment(.center).foregroundStyle(D.amber)
            Text("That's about \(model.library.milestones.firstTryLegal) extra scale fees you didn't pay.").foregroundStyle(D.muted)
            Button("Share") {
                model.showMilestone = false
                let card = ImageRenderer(content: VStack(spacing: 10) {
                    Text("\(model.library.milestones.firstTryLegal) legal on 1st re-weigh").font(.title.weight(.heavy)).foregroundStyle(D.amber)
                    Text("#TruckerTips #SlideYourTandems · Tandem Slide Calc").font(.subheadline).foregroundStyle(D.muted)
                }.padding(24).background(D.bg))
                card.scale = 3
                if let image = card.uiImage { model.shareResult(image) }
            }
            .buttonStyle(BigButton())
            .accessibilityIdentifier("milestone.share")
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .foregroundStyle(D.ink)
    }
}

struct PaywallView: View {
    @ObservedObject var purchases: Purchases
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "truck.box.fill").font(.system(size: 46)).foregroundStyle(D.amber)
                    Text("Unlock Tandem Slide Calc").font(.title.weight(.bold)).accessibilityIdentifier("paywall.title")
                    Text("One payment, yours for good. No subscription, no ads.").foregroundStyle(D.muted)
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(["Calibrates to your trailer from your own re-weighs",
                                 "Multiple tractors and trailers",
                                 "KPRA warning before the last legal hole",
                                 "Export scale history as CSV"], id: \.self) {
                            Label($0, systemImage: "checkmark.circle.fill").font(.subheadline)
                        }
                    }
                    .panel()
                    Text("Free forever: one rig and the basic slide advice.").font(.footnote).foregroundStyle(D.muted)
                    if let product = purchases.products.first(where: { $0.id == purchases.proID }) {
                        Button("Unlock for \(product.displayPrice)") { Task { await purchases.purchase(product) } }
                            .buttonStyle(BigButton())
                            .disabled(purchases.busy)
                    } else if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
                        Button("Unlock for $4.99") {}.buttonStyle(BigButton())
                    } else {
                        Button("Loading price…") {}.buttonStyle(BigButton()).disabled(true)
                    }
                    Button("Restore purchase") { Task { await purchases.restore() } }
                        .buttonStyle(BigButton(filled: false))
                    Text("The first 30 days include everything. After that, the free features keep working.")
                        .font(.caption).foregroundStyle(D.muted)
                }
                .padding(22)
            }
            .background(D.bg.ignoresSafeArea())
            .foregroundStyle(D.ink)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .task { await purchases.loadProducts() }
            .onChange(of: purchases.entitlement?.purchasedPro) { _, value in if value == true { dismiss() } }
            .alert("Notice", isPresented: Binding(get: { purchases.message != nil }, set: { if !$0 { purchases.message = nil } })) {
                Button("OK", role: .cancel) { purchases.message = nil }
            } message: { Text(purchases.message ?? "") }
        }
    }
}
