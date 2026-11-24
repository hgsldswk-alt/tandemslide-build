import StoreKit
import SwiftUI

struct WeighView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var focus: Field?
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var phase
    @State private var lastCalculated: Axles?

    private var reviewHome: Bool {
        model.tab == .weigh && focus == nil && model.reweighing == nil && model.share == nil && model.toast == nil
            && !model.showPaywall && !model.showMilestone && !model.purchases.busy && !model.testing
    }

    enum Field: Hashable { case steer, drive, trailer }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Menu {
                        ForEach(model.library.rigs) { rig in
                            Button(rig.name) { model.select(rig) }
                        }
                        Button("Add tractor/trailer…") { model.addRig() }
                    } label: {
                        Label(model.rig.name, systemImage: "chevron.down")
                            .font(.subheadline.weight(.bold))
                            .padding(.vertical, 6).padding(.horizontal, 10)
                            .background(D.raised, in: Capsule())
                    }
                    .accessibilityIdentifier("weigh.rig")
                    Spacer()
                    Text("\(model.rig.preset == .canada ? "Canada" : model.rig.preset == .custom ? "Custom" : "US Federal") · \(model.unit.rawValue)")
                        .font(.footnote).foregroundStyle(D.muted)
                }
                HStack(spacing: 8) {
                    field("Steer", text: $model.steer, field: .steer, over: over(\.steer))
                    field("Drive", text: $model.drive, field: .drive, over: over(\.drive))
                    field("Trailer", text: $model.trailer, field: .trailer, over: over(\.trailer))
                }
                if let reading = model.reading {
                    Text(summary(reading)).font(.footnote).foregroundStyle(D.muted)
                    if let advice = model.advice { AdviceCard(advice: advice) }
                    HStack(spacing: 10) {
                        Button("Log re-weigh") { focus = nil; model.startReweigh() }
                            .buttonStyle(BigButton())
                            .accessibilityIdentifier("weigh.reweigh")
                        Button("Share") {
                            focus = nil
                            if let advice = model.advice {
                                model.shareResult(ShareCard.render(advice: advice, unit: model.unit))
                            }
                        }
                        .buttonStyle(BigButton(filled: false))
                        .frame(width: 104)
                        .accessibilityIdentifier("weigh.share")
                    }
                    Button("New ticket") { model.clear(); focus = .steer }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(D.muted)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Type your CAT scale ticket").font(.headline)
                        Text("Steer, drive and trailer readings. The fix shows up as soon as all three are in.")
                            .font(.subheadline).foregroundStyle(D.muted)
                        Divider().overlay(D.line)
                        Text("Tandems toward the cab → weight moves from drive to trailer.\nTandems toward the rear → weight moves to drive.\nFifth wheel forward → steer gets heavier.")
                            .font(.footnote).foregroundStyle(D.muted)
                    }
                    .panel()
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: focus) { _, value in
            guard value == nil, let reading = model.reading, reading != lastCalculated, model.advice != nil else { return }
            lastCalculated = reading
            model.recordCalculation()
        }
        .onChange(of: model.reading) { _, value in if value == nil { lastCalculated = nil } }
        .reviewAfterCoreAction(when: reviewHome) { requestReview() }
        .task(id: reviewHome && model.reviewSignal > 0 && phase == .active) {
            guard reviewHome, model.reviewSignal > 0, phase == .active else { return }
            do { try await Task.sleep(for: .milliseconds(800)) } catch { return }
            guard !Task.isCancelled, reviewHome else { return }
            model.requestLegalReweighReview { requestReview() }
        }
        .background(D.bg.ignoresSafeArea())
        .onAppear { if model.reading == nil && !model.testing { focus = .steer } }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(focus == .trailer ? "Done" : "Next") { advance() }.fontWeight(.bold)
            }
        }
    }

    private func over(_ path: KeyPath<Axles, Double>) -> Bool {
        guard let r = model.reading else { return false }
        return r[keyPath: path] > model.rig.limits[keyPath: limitPath(path)]
    }

    private func limitPath(_ path: KeyPath<Axles, Double>) -> KeyPath<Limits, Double> {
        path == \Axles.steer ? \Limits.steer : path == \Axles.drive ? \Limits.drive : \Limits.trailer
    }

    private func summary(_ r: Axles) -> String {
        let limit = model.rig.limits
        let parts = [("Steer", r.steer - limit.steer), ("Drive", r.drive - limit.drive), ("Trailer", r.trailer - limit.trailer)]
            .filter { $0.1 > 0 }.map { "\($0.0) is \(model.unit.format($0.1)) over" }
        let gross = "Gross \(model.unit.format(r.gross)) / \(model.unit.format(limit.gross))"
        return parts.isEmpty ? gross : gross + " · " + parts.joined(separator: " · ")
    }

    private func advance() {
        switch focus {
        case .steer: focus = .drive
        case .drive: focus = .trailer
        default: focus = nil
        }
    }

    private func field(_ title: String, text: Binding<String>, field: Field, over: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(D.muted)
            TextField("0", text: text)
                .keyboardType(.numberPad)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(over ? D.red : D.ink)
                .minimumScaleFactor(0.6)
                .focused($focus, equals: field)
                .onChange(of: text.wrappedValue) { _, value in
                    if model.unit == .lb, value.filter(\.isNumber).count >= 5, focus == field { advance() }
                }
                .accessibilityIdentifier("weigh.\(field)")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(D.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(over ? D.red : (focus == field ? D.amber : D.line), lineWidth: over || focus == field ? 2 : 1))
    }
}

struct AdviceCard: View {
    @EnvironmentObject private var model: AppModel
    let advice: Advice

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch advice {
            case .legal:
                Text("ALREADY LEGAL").font(.caption.weight(.bold)).foregroundStyle(D.muted)
                Text("No move needed").font(.title.weight(.heavy)).foregroundStyle(D.green)
            case .unload(let over):
                Text("SLIDING WON'T FIX THIS").font(.caption.weight(.bold)).foregroundStyle(D.muted)
                Text("Gross is \(model.unit.format(over)) \(model.unit.rawValue) over — you need to unload.")
                    .font(.title2.weight(.heavy)).foregroundStyle(D.red)
            case .move(let move, _), .bestEffort(let move, _):
                if case .bestEffort = advice {
                    Text("CAN'T GET ALL AXLES LEGAL — CLOSEST").font(.caption.weight(.bold)).foregroundStyle(D.red)
                } else {
                    Text("DO THIS").font(.caption.weight(.bold)).foregroundStyle(D.muted)
                }
                Text(Self.headline(move)).font(.system(size: 25, weight: .heavy)).foregroundStyle(D.amber)
                    .accessibilityIdentifier("advice.headline")
                TruckDiagram(move: move)
                Text(Self.explain(move)).font(.footnote).foregroundStyle(D.muted)
            }
            if let predicted = advice.predicted {
                AxleBars(before: model.reading, after: predicted)
            }
            if model.hasPro && model.calibration.samples > 0 {
                Text("Using your calibration: \(Int(model.rates.perHole)) lb/hole from \(model.calibration.samples) re-weigh\(model.calibration.samples == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(D.green)
            } else {
                Text("Estimate: \(Int(model.rates.perHole)) lb per hole, \(Int(model.rates.perNotch)) lb per notch. Log re-weighs to calibrate.")
                    .font(.caption).foregroundStyle(D.muted)
            }
            if model.hasPro, let room = model.rig.rearRoom, let m = advice.move, m.holes < 0, -m.holes >= room {
                Label("This is the last legal hole toward the rear (KPRA).", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold)).foregroundStyle(D.amber)
            }
        }
        .panel(stroke: D.amber, width: 1.5)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("advice")
    }

    static func headline(_ m: Move) -> String {
        var parts: [String] = []
        if m.holes != 0 {
            parts.append("Slide tandems \(abs(m.holes)) hole\(abs(m.holes) == 1 ? "" : "s") toward the \(m.holes > 0 ? "CAB" : "REAR")")
        }
        if m.notches != 0 {
            parts.append("Fifth wheel \(abs(m.notches)) notch\(abs(m.notches) == 1 ? "" : "es") \(m.notches > 0 ? "FORWARD" : "BACK")")
        }
        return parts.isEmpty ? "No move needed" : parts.joined(separator: "\n+ ")
    }

    static func explain(_ m: Move) -> String {
        var parts: [String] = []
        if m.holes > 0 { parts.append("Toward the cab moves weight from drive to trailer.") }
        if m.holes < 0 { parts.append("Toward the rear moves weight from trailer to drive.") }
        if m.notches > 0 { parts.append("Fifth wheel forward moves weight from drive to steer.") }
        if m.notches < 0 { parts.append("Fifth wheel back moves weight from steer to drive.") }
        if m.notches == 0 { parts.append("Fifth wheel: no change.") }
        return parts.joined(separator: " ")
    }
}

struct AxleBars: View {
    @EnvironmentObject private var model: AppModel
    let before: Axles?
    let after: Axles

    var body: some View {
        let limits = model.rig.limits
        VStack(spacing: 10) {
            bar("Steer", before?.steer, after.steer, limits.steer)
            bar("Drive", before?.drive, after.drive, limits.drive)
            bar("Trailer", before?.trailer, after.trailer, limits.trailer)
        }
        .padding(.top, 4)
    }

    private func bar(_ name: String, _ now: Double?, _ value: Double, _ limit: Double) -> some View {
        let ok = value <= limit
        let u = model.unit
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name).font(.subheadline.weight(.bold))
                Spacer()
                Text("\(now.map { u.format($0) + " → " } ?? "")\(u.format(value)) / \(u.format(limit))")
                    .font(.caption.monospacedDigit()).foregroundStyle(D.muted)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(D.raised)
                    Capsule().fill(ok ? D.green : D.red).frame(width: geo.size.width * min(value / limit, 1))
                }
            }
            .frame(height: 9)
            Text(ok ? "+\(u.format(limit - value)) \(u.rawValue) margin" : "\(u.format(value - limit)) \(u.rawValue) over")
                .font(.caption).foregroundStyle(ok ? D.green : D.red)
        }
    }
}

struct ReweighSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let weigh: Weigh
    @State private var steer = ""
    @State private var drive = ""
    @State private var trailer = ""
    @State private var place = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("You moved") {
                    Text(AdviceCard.headline(weigh.moved)).font(.headline)
                }
                Section("Second scale ticket (\(model.unit.rawValue))") {
                    TextField("Steer", text: $steer).keyboardType(.numberPad).focused($focused).accessibilityIdentifier("reweigh.steer")
                    TextField("Drive", text: $drive).keyboardType(.numberPad).accessibilityIdentifier("reweigh.drive")
                    TextField("Trailer", text: $trailer).keyboardType(.numberPad).accessibilityIdentifier("reweigh.trailer")
                    TextField("Scale location (optional)", text: $place)
                }
                if let p = weigh.predicted {
                    Section("Predicted") {
                        Text("Steer \(model.unit.format(p.steer)) · Drive \(model.unit.format(p.drive)) · Trailer \(model.unit.format(p.trailer))")
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Log re-weigh")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Later") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let s = model.parse(steer), let d = model.parse(drive), let t = model.parse(trailer) {
                            if let i = model.library.weighs.firstIndex(where: { $0.id == weigh.id }) {
                                model.library.weighs[i].place = String(place.prefix(40))
                            }
                            model.saveReweigh(weigh, after: Axles(steer: s, drive: d, trailer: t))
                        }
                    }
                    .fontWeight(.bold)
                    .disabled(model.parse(steer) == nil || model.parse(drive) == nil || model.parse(trailer) == nil)
                    .accessibilityIdentifier("reweigh.save")
                }
            }
            .onAppear { if !model.testing { focused = true } }
        }
    }
}
