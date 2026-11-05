import Testing
@testable import Ghostty

struct UpdateFeedTests {
    @Test func forkNeverResolvesAFeedURL() {
        #expect(UpdateFeed.urlString == nil)
        #expect(UpdateFeed.isInert)
    }
}
