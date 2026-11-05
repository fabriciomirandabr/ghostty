import Testing
@testable import Ghostty

struct WorkspaceSwitcherFilterTests {
    private func entries() -> [WorkspaceSwitcherEntry] {
        let snapshot = OverlayFixtures.snapshot([
            OverlayFixtures.workspace("Default", directory: OverlayFixtures.home, isDefault: true),
            OverlayFixtures.workspace("api", directory: "\(OverlayFixtures.home)/Code/api"),
            OverlayFixtures.workspace("Web", directory: "\(OverlayFixtures.home)/Code/web-app"),
            OverlayFixtures.workspace("docs", directory: "/srv/docs"),
        ])
        return WorkspaceSwitcherFilter.entries(from: snapshot, home: OverlayFixtures.home)
    }

    @Test func entriesUseAbbreviatedFolders() {
        #expect(entries().map(\.folder) == ["~", "~/Code/api", "~/Code/web-app", "/srv/docs"])
    }

    @Test func emptyQueryReturnsEverything() {
        let all = entries()
        #expect(WorkspaceSwitcherFilter.matches(all, query: "") == all)
        #expect(WorkspaceSwitcherFilter.matches(all, query: "   ") == all)
    }

    @Test func matchesByNameIgnoringCase() {
        let result = WorkspaceSwitcherFilter.matches(entries(), query: "WEB")
        #expect(result.map(\.name) == ["Web"])
    }

    @Test func matchesByFolder() {
        let result = WorkspaceSwitcherFilter.matches(entries(), query: "code/")
        #expect(result.map(\.name) == ["api", "Web"])
        #expect(WorkspaceSwitcherFilter.matches(entries(), query: "/SRV").map(\.name) == ["docs"])
    }

    @Test func queryIsTrimmed() {
        #expect(WorkspaceSwitcherFilter.matches(entries(), query: "  api ").map(\.name) == ["api"])
    }

    @Test func noResultWhenNothingMatches() {
        #expect(WorkspaceSwitcherFilter.matches(entries(), query: "zzz").isEmpty)
    }

    @Test func resultsKeepStoreOrder() {
        let result = WorkspaceSwitcherFilter.matches(entries(), query: "a")
        #expect(result.map(\.name) == ["Default", "api", "Web"])
    }

    @Test func selectionWrapsAround() {
        #expect(WorkspaceSwitcherFilter.moved(from: 0, by: -1, count: 3) == 2)
        #expect(WorkspaceSwitcherFilter.moved(from: 2, by: 1, count: 3) == 0)
        #expect(WorkspaceSwitcherFilter.moved(from: 1, by: 1, count: 3) == 2)
        #expect(WorkspaceSwitcherFilter.moved(from: 0, by: 1, count: 0) == 0)
    }

    @Test func selectionClampsToResults() {
        #expect(WorkspaceSwitcherFilter.clamped(5, count: 2) == 1)
        #expect(WorkspaceSwitcherFilter.clamped(-1, count: 2) == 0)
        #expect(WorkspaceSwitcherFilter.clamped(3, count: 0) == 0)
    }
}
