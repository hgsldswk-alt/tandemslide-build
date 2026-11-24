import Foundation
import XCTest

final class CoreTests: XCTestCase {
    private let fed = Limits.usFederal
    private let rates = Rates()

    func testDirectionRules() {
        let a = Axles(steer: 11_000, drive: 34_000, trailer: 33_000)
        let cab = AxleMath.apply(Move(holes: 2, notches: 0), to: a, rates: rates)
        XCTAssertEqual(cab.drive, 33_500)
        XCTAssertEqual(cab.trailer, 33_500)
        XCTAssertEqual(cab.steer, 11_000)
        let rear = AxleMath.apply(Move(holes: -2, notches: 0), to: a, rates: rates)
        XCTAssertEqual(rear.drive, 34_500)
        XCTAssertEqual(rear.trailer, 32_500)
        let forward = AxleMath.apply(Move(holes: 0, notches: 1), to: a, rates: rates)
        XCTAssertEqual(forward.steer, 11_500)
        XCTAssertEqual(forward.drive, 33_500)
        XCTAssertEqual(cab.gross, a.gross)
        XCTAssertEqual(forward.gross, a.gross)
    }

    func testAlreadyLegal() {
        let a = Axles(steer: 11_000, drive: 33_000, trailer: 33_000)
        XCTAssertEqual(AxleMath.solve(a, limits: fed, rates: rates), .legal(a))
    }

    func testDriveOverSlidesTowardCabRoundingUp() {
        let a = Axles(steer: 11_450, drive: 35_100, trailer: 32_400)
        guard case .move(let m, let p) = AxleMath.solve(a, limits: fed, rates: rates) else { return XCTFail() }
        XCTAssertEqual(m, Move(holes: 5, notches: 0))
        XCTAssertEqual(p.drive, 33_850)
        XCTAssertEqual(p.trailer, 33_650)
    }

    func testTrailerOverSlidesTowardRear() {
        let a = Axles(steer: 11_300, drive: 33_100, trailer: 34_700)
        guard case .move(let m, _) = AxleMath.solve(a, limits: fed, rates: rates) else { return XCTFail() }
        XCTAssertEqual(m.holes, -3)
        XCTAssertEqual(m.notches, 0)
    }

    func testSteerOverUsesFifthWheelBack() {
        let a = Axles(steer: 12_350, drive: 33_000, trailer: 32_000)
        guard case .move(let m, let p) = AxleMath.solve(a, limits: fed, rates: rates) else { return XCTFail() }
        XCTAssertEqual(m.notches, -1)
        XCTAssertTrue(fed.isLegal(p))
    }

    func testBothDriveAndTrailerOverNeedsBoth() {
        let a = Axles(steer: 10_500, drive: 34_600, trailer: 34_200)
        guard case .move(let m, let p) = AxleMath.solve(a, limits: fed, rates: rates) else { return XCTFail() }
        XCTAssertGreaterThan(m.notches, 0)
        XCTAssertTrue(fed.isLegal(p))
    }

    func testGrossOverMeansUnload() {
        let a = Axles(steer: 12_000, drive: 35_000, trailer: 34_500)
        XCTAssertEqual(AxleMath.solve(a, limits: fed, rates: rates), .unload(1_500))
    }

    func testKPRABlocksRearSlide() {
        let a = Axles(steer: 11_300, drive: 33_100, trailer: 34_700)
        let advice = AxleMath.solve(a, limits: fed, rates: rates, rearRoom: 2)
        XCTAssertNotEqual(advice.move?.holes, -3)
        if let holes = advice.move?.holes { XCTAssertGreaterThanOrEqual(holes, -2) }
    }

    func testBestEffortWhenImpossible() {
        let tight = Limits(steer: 12_000, drive: 34_000, trailer: 34_000, gross: 90_000)
        let a = Axles(steer: 12_000, drive: 39_000, trailer: 39_000)
        guard case .bestEffort = AxleMath.solve(a, limits: tight, rates: rates) else { return XCTFail() }
    }

    func testCalibrationLeastSquares() {
        let rig = UUID()
        func w(_ h: Int, _ dt: Double) -> Weigh {
            let before = Axles(steer: 11_000, drive: 35_000, trailer: 32_000)
            return Weigh(rigID: rig, before: before, moved: Move(holes: h, notches: 0),
                         after: Axles(steer: 11_000, drive: 35_000 - dt, trailer: 32_000 + dt))
        }
        let c = Calibration.fit([w(4, 1_040), w(2, 540), w(-3, -780)], defaults: rates)
        XCTAssertEqual(c.samples, 3)
        let expected: Double = (4.0 * 1_040 + 2.0 * 540 + 3.0 * 780) / 29.0
        XCTAssertEqual(c.rates.perHole, expected, accuracy: 0.01)
        XCTAssertEqual(c.rates.perNotch, 500)
        XCTAssertNotNil(c.error)
        let none = Calibration.fit([Weigh(rigID: rig, before: Axles(steer: 1, drive: 1, trailer: 1), moved: Move())], defaults: rates)
        XCTAssertEqual(none.samples, 0)
        XCTAssertEqual(none.rates, rates)
    }

    func testCalibrationIsClamped() {
        let rig = UUID()
        let crazy = Weigh(rigID: rig, before: Axles(steer: 0, drive: 40_000, trailer: 0), moved: Move(holes: 1, notches: 0),
                          after: Axles(steer: 0, drive: 30_000, trailer: 10_000))
        XCTAssertEqual(Calibration.fit([crazy], defaults: rates).rates.perHole, 800)
    }

    func testUnitsRoundTrip() {
        XCTAssertEqual(WeightUnit.kg.store(17_000), 37_479)
        XCTAssertEqual(WeightUnit.lb.store(34_000), 34_000)
        XCTAssertEqual(WeightUnit.kg.show(WeightUnit.kg.store(5_500)), 5_500, accuracy: 0.5)
        XCTAssertEqual(Limits.canada.gross, 87_083)
    }

    func testTrailerCodeRoundTripAndValidation() throws {
        var rig = Rig()
        rig.trailer = "Fleet 53 reefer"
        rig.holeSpacing = 6
        let code = TrailerCode.make(rig, calibrated: Rates(perHole: 262.4, perNotch: 480))
        let p = try XCTUnwrap(TrailerCode.decode("hey use this: \(code) thanks"))
        XCTAssertEqual(p.perHole, 262)
        XCTAssertEqual(p.trailer, "Fleet 53 reefer")
        var other = Rig()
        TrailerCode.apply(p, to: &other)
        XCTAssertEqual(other.rates.perHole, 262)
        XCTAssertNil(TrailerCode.decode("TSC1:garbage"))
        XCTAssertNil(TrailerCode.decode("nothing here"))
        let bad = TrailerCode.make(rig, calibrated: Rates(perHole: 5_000, perNotch: 480))
        XCTAssertNil(TrailerCode.decode(bad))
    }

    func testCSVEscapesTextOnly() {
        let rig = Rig()
        var w = Weigh(rigID: rig.id, before: Axles(steer: 11_000, drive: 34_000, trailer: 33_000), moved: Move(holes: -2, notches: 0))
        w.place = "=cmd, \"x\""
        let csv = CSVExport.make([w], rigs: [rig], unit: .lb)
        XCTAssertTrue(csv.contains("\"'=cmd, \"\"x\"\"\""))
        XCTAssertTrue(csv.contains(",-2,0,"))
    }

    func testCoreReviewRequiresThreeActionsOnTwoLocalDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let firstDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 23)))
        let nextDay = firstDay.addingTimeInterval(2 * 3600)
        let empty = try JSONDecoder().decode(CoreReviewProgress.self, from: Data("{}".utf8))
        XCTAssertFalse(empty.isEligible)
        var progress = CoreReviewProgress.recording(empty, at: firstDay, calendar: calendar)
        var twoDays = progress
        twoDays.record(at: nextDay, calendar: calendar)
        XCTAssertFalse(twoDays.isEligible)
        progress.record(at: firstDay, calendar: calendar)
        XCTAssertFalse(progress.isEligible)

        var sameDay = progress
        sameDay.record(at: firstDay, calendar: calendar)
        XCTAssertFalse(sameDay.isEligible)

        let data = try JSONEncoder().encode(progress)
        progress = try JSONDecoder().decode(CoreReviewProgress.self, from: data)
        progress.record(at: nextDay, calendar: calendar)
        XCTAssertTrue(progress.isEligible)
    }

    func testReviewOnceAfterThirdLegal() {
        var gate = ReviewGate()
        XCTAssertFalse(gate.shouldAsk(legalReweighs: 2))
        XCTAssertTrue(gate.shouldAsk(legalReweighs: 3))
        XCTAssertFalse(gate.shouldAsk(legalReweighs: 4))
    }

    func testTrialThirtyDays() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        var e = Entitlement(firstOpen: start)
        e.proStartedAt = start
        XCTAssertTrue(e.hasPro(at: start.addingTimeInterval(29 * 86_400), free: false))
        XCTAssertFalse(e.hasPro(at: start.addingTimeInterval(31 * 86_400), free: false))
        e.purchasedPro = true
        XCTAssertTrue(e.hasPro(at: start.addingTimeInterval(400 * 86_400), free: false))
    }
}
