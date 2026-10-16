import XCTest
@testable import LaunchpadProCodex

final class LaunchModelReloadTests: XCTestCase {
    private func app(_ name: String) -> AppRecord {
        let path = "/Applications/\(name).app"
        return AppRecord(id: path, name: name, originalName: name, path: path,
                         bundleIdentifier: "test.\(name)", dateAdded: 0)
    }

    func testOnlyLatestRequestedGenerationAppliesInEitherCompletionOrder() {
        let initial = [app("Initial")]
        let results = [[app("Older")], [app("Latest")]]
        for order in [[1, 2], [2, 1]] {
            var current = initial
            var appliedGenerations: [Int] = []
            for generation in order {
                let scanned = results[generation - 1]
                if LaunchModel.shouldApplyReload(scanned, currentApps: current,
                                                 generation: generation, currentGeneration: 2,
                                                 force: false) {
                    current = scanned
                    appliedGenerations.append(generation)
                }
            }
            XCTAssertEqual(current, results[1])
            XCTAssertEqual(appliedGenerations, [2])
        }
    }

    func testUnchangedLatestResultStillInvalidatesOlderChangedResult() {
        let current = [app("Current")]
        XCTAssertFalse(LaunchModel.shouldApplyReload(current, currentApps: current,
                                                     generation: 2, currentGeneration: 2,
                                                     force: false))
        XCTAssertFalse(LaunchModel.shouldApplyReload([app("Older")], currentApps: current,
                                                     generation: 1, currentGeneration: 2,
                                                     force: false))
    }

    func testForceReappliesEqualResultButCannotReviveStaleGeneration() {
        let current = [app("Current")]
        XCTAssertTrue(LaunchModel.shouldApplyReload(current, currentApps: current,
                                                    generation: 2, currentGeneration: 2,
                                                    force: true))
        for scanned in [current, [app("Older")]] {
            XCTAssertFalse(LaunchModel.shouldApplyReload(scanned, currentApps: current,
                                                         generation: 1, currentGeneration: 2,
                                                         force: true))
        }
    }

    func testLatestScanAppliesAdditionsRemovalsAndRecordChanges() {
        let original = app("Current")
        var renamed = original
        renamed.name = "Updated name"
        var changedBundle = original
        changedBundle.bundleIdentifier = "test.updated"
        var changedDate = original
        changedDate.dateAdded = 42
        for scanned in [[], [original, app("New")], [renamed], [changedBundle], [changedDate]] {
            XCTAssertTrue(LaunchModel.shouldApplyReload(scanned, currentApps: [original],
                                                        generation: 3, currentGeneration: 3,
                                                        force: false))
        }
        XCTAssertFalse(LaunchModel.shouldApplyReload([], currentApps: [],
                                                     generation: 3, currentGeneration: 3,
                                                     force: false))
        XCTAssertTrue(LaunchModel.shouldApplyReload([], currentApps: [],
                                                    generation: 3, currentGeneration: 3,
                                                    force: true))
    }
}
