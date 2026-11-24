import SwiftUI
import UIKit

struct ShareItems: Identifiable {
    let id = UUID()
    let items: [Any]
}

enum Tab: Hashable { case weigh, history, rig }

@MainActor
final class AppModel: ObservableObject {
    @Published var library = Library() { didSet { if library != oldValue { persist() } } }
    @Published var tab: Tab = .weigh
    @Published var steer = ""
    @Published var drive = ""
    @Published var trailer = ""
    @Published var reweighing: Weigh?
    @Published var share: ShareItems?
    @Published var showPaywall = false
    @Published var showMilestone = false
    @Published var toast: String?
    @Published var reviewSignal = 0
    @Published var now = Date()

    let testing: Bool
    let expired: Bool
    let purchases = Purchases.shared
    private let url: URL
    private var toastTask: Task<Void, Never>?
    private var savedLibrary = false

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        testing = Launch.has("-ui-testing", in: arguments)
        expired = Launch.has("-expired", in: arguments) || Launch.has("-paywall", in: arguments)
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        url = base.appendingPathComponent(testing ? "tandemslide-ui-\(Launch.value("-data-id", in: arguments) ?? "x").json" : "tandemslide.json")
        if testing && Launch.has("-reset", in: arguments) { try? FileManager.default.removeItem(at: url) }
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode(Library.self, from: data) {
            library = saved
        }
        if testing, let fixture = Launch.value("-fixture", in: arguments) { Fixtures.apply(fixture, to: self) }
        now = Date()
    }

    func start() async {
        await purchases.start(now: Date(), testing: testing, expired: expired)
        now = Date()
        if Launch.has("-paywall") { showPaywall = true }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(library)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            savedLibrary = true
        } catch { savedLibrary = false }
    }

    var hasPro: Bool { purchases.hasPro(at: now) }
    var unit: WeightUnit { library.unit }
    var rig: Rig { library.rig }
    var calibration: Calibration { library.calibration(for: rig) }
    var rates: Rates { hasPro ? calibration.rates : rig.rates }

    func parse(_ text: String) -> Double? {
        let digits = text.filter { $0.isNumber || $0 == "." }
        guard let value = Double(digits), value > 0, value < 200_000 else { return nil }
        return unit.store(value)
    }

    var reading: Axles? {
        guard let s = parse(steer), let d = parse(drive), let t = parse(trailer) else { return nil }
        return Axles(steer: s, drive: d, trailer: t)
    }

    var advice: Advice? {
        reading.map { AxleMath.solve($0, limits: rig.limits, rates: rates, rearRoom: hasPro ? rig.rearRoom : nil) }
    }

    func recordCalculation() {
        guard !testing, advice != nil else { return }
        library.coreReviewProgress = .recording(library.coreReviewProgress)
        if savedLibrary { CoreReview.shared.record(library.coreReviewProgress) }
    }

    func clear() {
        steer = ""; drive = ""; trailer = ""
    }

    func notify(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            if !Task.isCancelled { self.toast = nil }
        }
    }


    func startReweigh() {
        guard let reading, let advice else { return }
        let weigh = Weigh(rigID: rig.id, before: reading, moved: advice.move ?? Move(), predicted: advice.predicted)
        library.weighs.insert(weigh, at: 0)
        reweighing = weigh
    }

    func saveReweigh(_ weigh: Weigh, after: Axles) {
        guard let i = library.weighs.firstIndex(where: { $0.id == weigh.id }) else { return }
        library.weighs[i].after = after
        reweighing = nil
        let legal = rig.limits.isLegal(after)
        if legal { library.milestones.firstTryLegal += 1 }
        notify(legal ? "Re-weigh logged — all axles legal" : "Re-weigh logged — calibration updated")
        clear()
        if library.milestones.firstTryLegal >= 10 && !library.milestones.shownTen {
            library.milestones.shownTen = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 700_000_000)
                self.showMilestone = true
            }
        }
        if legal && !testing { reviewSignal += 1 }
    }

    func requestLegalReweighReview(_ request: () -> Void) {
        var next = library.review
        guard CoreReview.shared.attempt(ifEligible: { next.shouldAsk(legalReweighs: library.legalReweighs(for: rig)) }, request) else { return }
        library.review = next
    }

    func deleteWeigh(_ id: UUID) { library.weighs.removeAll { $0.id == id } }


    func addRig() {
        guard hasPro else { showPaywall = true; return }
        var rig = Rig()
        rig.tractor = "Tractor \(library.rigs.count + 1)"
        library.rigs.append(rig)
        library.currentRig = rig.id
    }

    func select(_ rig: Rig) {
        guard hasPro || rig.id == library.rigs.first?.id else { showPaywall = true; return }
        library.currentRig = rig.id
    }

    func updateRig(_ change: (inout Rig) -> Void) {
        var rig = library.rig
        change(&rig)
        library.rig = rig
    }


    func shareResult(_ image: UIImage) {
        share = ShareItems(items: [image, "Scale ticket to legal with Tandem Slide Calc #TruckerTips #SlideYourTandems"])
    }

    func copyTrailerCode() {
        UIPasteboard.general.string = "Our trailer settings for Tandem Slide Calc:\n" + TrailerCode.make(rig, calibrated: rates)
        notify("Trailer code copied")
    }

    func importTrailerCode(_ text: String?) {
        guard let text, let payload = TrailerCode.decode(text) else { return notify("No trailer code found on the clipboard") }
        updateRig { TrailerCode.apply(payload, to: &$0) }
        notify("Imported \(payload.trailer): \(Int(payload.perHole)) lb/hole")
    }

    func exportCSV() {
        guard hasPro else { showPaywall = true; return }
        let text = CSVExport.make(library.weighs, rigs: library.rigs, unit: unit)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("Scale history.csv")
        do {
            try Data(text.utf8).write(to: file, options: .atomic)
            share = ShareItems(items: [file])
        } catch { notify("Export failed") }
    }
}

enum Fixtures {
    @MainActor
    static func apply(_ name: String, to model: AppModel) {
        var lib = Library()
        lib.rigs[0].tractor = "Pete 579"
        lib.rigs[0].trailer = "Utility 53′"
        lib.rigs[0].rearRoom = 6
        let id = lib.rigs[0].id
        let day: TimeInterval = 86_400
        let samples: [(String, Double, Axles, Move, Axles)] = [
            ("Joplin, MO", 1, Axles(steer: 11_450, drive: 35_100, trailer: 32_400), Move(holes: 5, notches: 0),
             Axles(steer: 11_460, drive: 33_790, trailer: 33_700)),
            ("Amarillo, TX", 4, Axles(steer: 11_300, drive: 33_100, trailer: 34_700), Move(holes: -3, notches: 0),
             Axles(steer: 11_290, drive: 33_910, trailer: 33_900)),
            ("Barstow, CA", 8, Axles(steer: 12_350, drive: 34_300, trailer: 31_900), Move(holes: 2, notches: -1),
             Axles(steer: 11_880, drive: 34_120, trailer: 32_450)),
            ("Gary, IN", 12, Axles(steer: 11_600, drive: 34_900, trailer: 32_800), Move(holes: 4, notches: 0),
             Axles(steer: 11_610, drive: 33_850, trailer: 33_840)),
        ]
        for (place, ago, before, move, after) in samples {
            var w = Weigh(rigID: id, before: before, moved: move, predicted: AxleMath.apply(move, to: before, rates: Rates()), after: after)
            w.place = place
            w.date = Date().addingTimeInterval(-ago * day)
            lib.weighs.append(w)
        }
        lib.milestones.firstTryLegal = name == "milestone" ? 9 : 3
        model.library = lib
        if name != "empty-input" {
            model.steer = "11450"; model.drive = "35100"; model.trailer = "32400"
        }
    }
}
