import Foundation

enum Launch {
    static let freePeriod = false
    static func isFree(arguments: [String]) -> Bool {
        freePeriod && !arguments.contains(where: { ["-paid-mode", "-paywall", "-expired"].contains($0) })
    }
    static var isFree: Bool { isFree(arguments: ProcessInfo.processInfo.arguments) }
    static func has(_ flag: String, in args: [String] = ProcessInfo.processInfo.arguments) -> Bool { args.contains(flag) }
    static func value(_ flag: String, in args: [String] = ProcessInfo.processInfo.arguments) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}

enum WeightUnit: String, Codable, CaseIterable, Identifiable {
    case lb, kg
    var id: String { rawValue }

    func show(_ lb: Double) -> Double { self == .lb ? lb : Units.kg(fromLb: lb) }
    func store(_ value: Double) -> Double { self == .lb ? value : Units.lb(fromKg: value) }

    func format(_ lb: Double, signed: Bool = false) -> String {
        let value = show(lb)
        let rounded = self == .lb ? (value / 10).rounded() * 10 : (value / 5).rounded() * 5
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        if signed { formatter.positivePrefix = "+" }
        return formatter.string(from: NSNumber(value: rounded == 0 ? 0 : rounded)) ?? "\(Int(rounded))"
    }
}

struct Rig: Codable, Equatable, Identifiable {
    var id = UUID()
    var tractor = "My tractor"
    var trailer = "53′ trailer"
    var rates = Rates()
    var holeSpacing = 6
    var rearRoom: Int?
    var preset: LimitPreset = .usFederal
    var custom = Limits.usFederal

    var name: String { "\(tractor) + \(trailer)" }

    var limits: Limits {
        switch preset {
        case .usFederal: .usFederal
        case .canada: .canada
        case .custom: custom
        }
    }
}

struct Milestones: Codable, Equatable {
    var firstTryLegal = 0
    var shownTen = false
}

struct ReviewGate: Codable, Equatable {
    private(set) var requested = false

    mutating func shouldAsk(legalReweighs: Int) -> Bool {
        guard !requested, legalReweighs >= 3 else { return false }
        requested = true
        return true
    }
}

struct Library: Codable, Equatable {
    var coreReviewProgress: CoreReviewProgress?
    var rigs: [Rig] = [Rig()]
    var currentRig: UUID?
    var weighs: [Weigh] = []
    var unit: WeightUnit = .lb
    var milestones = Milestones()
    var review = ReviewGate()

    var rig: Rig {
        get { rigs.first { $0.id == currentRig } ?? rigs[0] }
        set {
            if let i = rigs.firstIndex(where: { $0.id == newValue.id }) { rigs[i] = newValue } else { rigs.append(newValue) }
        }
    }

    func weighs(for rig: Rig) -> [Weigh] { weighs.filter { $0.rigID == rig.id } }

    func calibration(for rig: Rig) -> Calibration {
        Calibration.fit(weighs(for: rig), defaults: rig.rates)
    }

    func legalReweighs(for rig: Rig) -> Int {
        weighs.filter { w in w.after.map { a in (rigs.first { $0.id == w.rigID } ?? rig).limits.isLegal(a) } ?? false }.count
    }
}

enum TrailerCode {
    static let prefix = "TSC1:"

    struct Payload: Codable, Equatable {
        var trailer: String
        var perHole: Double
        var perNotch: Double
        var holeSpacing: Int
        var preset: LimitPreset
        var custom: Limits
    }

    static func make(_ rig: Rig, calibrated: Rates) -> String {
        let payload = Payload(trailer: rig.trailer, perHole: calibrated.perHole.rounded(), perNotch: calibrated.perNotch.rounded(),
                              holeSpacing: rig.holeSpacing, preset: rig.preset, custom: rig.custom)
        let data = (try? JSONEncoder().encode(payload)) ?? Data()
        return prefix + data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ text: String) -> Payload? {
        guard text.count < 4_000, let start = text.range(of: prefix) else { return nil }
        let body = text[start.upperBound...].prefix { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        var b64 = body.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard !body.isEmpty, let data = Data(base64Encoded: b64),
              var p = try? JSONDecoder().decode(Payload.self, from: data),
              (50...800).contains(p.perHole), (100...1_500).contains(p.perNotch), (1...24).contains(p.holeSpacing),
              [p.custom.steer, p.custom.drive, p.custom.trailer, p.custom.gross].allSatisfy({ (1_000...200_000).contains($0) })
        else { return nil }
        p.trailer = String(p.trailer.prefix(40))
        return p
    }

    static func apply(_ p: Payload, to rig: inout Rig) {
        rig.trailer = p.trailer
        rig.rates = Rates(perHole: p.perHole, perNotch: p.perNotch)
        rig.holeSpacing = p.holeSpacing
        rig.preset = p.preset
        rig.custom = p.custom
    }
}

enum CSVExport {
    static func make(_ weighs: [Weigh], rigs: [Rig], unit: WeightUnit) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        var rows = ["date,place,rig,steer,drive,trailer,gross,holes_toward_cab,notches_forward,predicted_drive,reweigh_steer,reweigh_drive,reweigh_trailer,unit"]
        for w in weighs.sorted(by: { $0.date < $1.date }) {
            let rig = rigs.first { $0.id == w.rigID }?.name ?? ""
            func n(_ v: Double?) -> String { v.map { String(Int(unit.show($0).rounded())) } ?? "" }
            let cells = [f.string(from: w.date), escape(w.place), escape(rig), n(w.before.steer), n(w.before.drive), n(w.before.trailer),
                         n(w.before.gross), String(w.moved.holes), String(w.moved.notches), n(w.predicted?.drive),
                         n(w.after?.steer), n(w.after?.drive), n(w.after?.trailer), unit.rawValue]
            rows.append(cells.joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    static func escape(_ s: String) -> String {
        var s = s
        if let first = s.first, "=+-@".contains(first) { s = "'" + s }
        return s.contains(where: { ",\"\n".contains($0) }) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
    }
}
