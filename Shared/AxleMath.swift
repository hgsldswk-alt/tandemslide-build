import Foundation

struct Axles: Codable, Equatable {
    var steer: Double
    var drive: Double
    var trailer: Double

    var gross: Double { steer + drive + trailer }
}

struct Limits: Codable, Equatable {
    var steer: Double
    var drive: Double
    var trailer: Double
    var gross: Double

    static let usFederal = Limits(steer: 12_000, drive: 34_000, trailer: 34_000, gross: 80_000)
    static let canada = Limits(steer: Units.lb(fromKg: 5_500), drive: Units.lb(fromKg: 17_000),
                               trailer: Units.lb(fromKg: 17_000), gross: Units.lb(fromKg: 39_500))

    func margins(_ a: Axles) -> Axles {
        Axles(steer: steer - a.steer, drive: drive - a.drive, trailer: trailer - a.trailer)
    }

    func isLegal(_ a: Axles) -> Bool {
        a.steer <= steer && a.drive <= drive && a.trailer <= trailer && a.gross <= gross
    }

    func overweight(_ a: Axles) -> Double {
        max(0, a.steer - steer) + max(0, a.drive - drive) + max(0, a.trailer - trailer)
    }
}

enum LimitPreset: String, Codable, CaseIterable, Identifiable {
    case usFederal, canada, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .usFederal: "US Federal (12k / 34k / 34k / 80k)"
        case .canada: "Canada typical (5.5t / 17t / 17t / 39.5t)"
        case .custom: "Custom"
        }
    }
}

enum Units {
    static let kgPerLb = 0.45359237
    static func lb(fromKg kg: Double) -> Double { (kg / kgPerLb).rounded() }
    static func kg(fromLb lb: Double) -> Double { lb * kgPerLb }
}

struct Move: Codable, Equatable {
    var holes = 0
    var notches = 0

    var isNone: Bool { holes == 0 && notches == 0 }
    var size: Int { abs(holes) + abs(notches) }
}

struct Rates: Codable, Equatable {
    var perHole: Double = 250
    var perNotch: Double = 500
}

enum Advice: Equatable {
    case legal(Axles)
    case move(Move, Axles)
    case unload(Double)
    case bestEffort(Move, Axles)

    var move: Move? {
        switch self {
        case .move(let m, _), .bestEffort(let m, _): m
        default: nil
        }
    }

    var predicted: Axles? {
        switch self {
        case .legal(let a), .move(_, let a), .bestEffort(_, let a): a
        case .unload: nil
        }
    }
}

enum AxleMath {
    static let maxHoles = 20
    static let maxNotches = 8

    static func apply(_ move: Move, to a: Axles, rates: Rates) -> Axles {
        let h = Double(move.holes) * rates.perHole
        let n = Double(move.notches) * rates.perNotch
        return Axles(steer: a.steer + n, drive: a.drive - h - n, trailer: a.trailer + h)
    }

    static func solve(_ a: Axles, limits: Limits, rates: Rates, rearRoom: Int? = nil) -> Advice {
        if limits.isLegal(a) { return .legal(a) }
        if a.gross > limits.gross { return .unload(a.gross - limits.gross) }
        var best: (move: Move, axles: Axles, cost: Int, margin: Double)?
        var fallback: (move: Move, axles: Axles, over: Double, cost: Int)?
        for holes in -maxHoles...maxHoles {
            if let rearRoom, holes < 0, -holes > rearRoom { continue }
            for notches in -maxNotches...maxNotches {
                let move = Move(holes: holes, notches: notches)
                let result = apply(move, to: a, rates: rates)
                let cost = abs(holes) + 2 * abs(notches)
                if limits.isLegal(result) {
                    let m = limits.margins(result)
                    let margin = min(m.steer, m.drive, m.trailer)
                    if best == nil || cost < best!.cost || (cost == best!.cost && margin > best!.margin) {
                        best = (move, result, cost, margin)
                    }
                } else {
                    let over = limits.overweight(result)
                    if fallback == nil || over < fallback!.over - 0.5 || (abs(over - fallback!.over) <= 0.5 && cost < fallback!.cost) {
                        fallback = (move, result, over, cost)
                    }
                }
            }
        }
        if let best { return .move(best.move, best.axles) }
        if let fallback, !fallback.move.isNone { return .bestEffort(fallback.move, fallback.axles) }
        return .bestEffort(Move(), a)
    }
}

struct Weigh: Codable, Equatable, Identifiable {
    var id = UUID()
    var date = Date()
    var rigID: UUID
    var before: Axles
    var moved: Move
    var predicted: Axles?
    var after: Axles?
    var place = ""
}

struct Calibration: Equatable {
    var rates: Rates
    var samples: Int
    var error: Double?

    static func fit(_ weighs: [Weigh], defaults: Rates) -> Calibration {
        var hh = 0.0, ht = 0.0, nn = 0.0, ns = 0.0
        var used: [Weigh] = []
        for w in weighs {
            guard let after = w.after, !w.moved.isNone else { continue }
            let h = Double(w.moved.holes), n = Double(w.moved.notches)
            hh += h * h; ht += h * (after.trailer - w.before.trailer)
            nn += n * n; ns += n * (after.steer - w.before.steer)
            used.append(w)
        }
        var rates = defaults
        if hh > 0 { rates.perHole = min(max(ht / hh, 50), 800) }
        if nn > 0 { rates.perNotch = min(max(ns / nn, 100), 1_500) }
        guard !used.isEmpty else { return Calibration(rates: defaults, samples: 0, error: nil) }
        let residuals = used.map { w -> Double in
            let p = AxleMath.apply(w.moved, to: w.before, rates: rates)
            return w.after!.drive - p.drive
        }
        let rms = (residuals.map { $0 * $0 }.reduce(0, +) / Double(residuals.count)).squareRoot()
        return Calibration(rates: rates, samples: used.count, error: (rms / 10).rounded() * 10)
    }
}
