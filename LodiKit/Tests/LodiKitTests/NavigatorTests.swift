import Testing
@testable import LodiKit

@MainActor
struct NavigatorTests {
    @Test func startsOnTheBoard() {
        let navigator = Navigator()
        #expect(navigator.destination == .board)
        #expect(navigator.isPaletteVisible == false)
        #expect(navigator.isAssistantVisible == false)
    }

    @Test func goChangesDestination() {
        let navigator = Navigator()
        navigator.go(to: .tool(.webPro))
        #expect(navigator.destination == .tool(.webPro))
    }

    @Test func goClosesThePalette() {
        let navigator = Navigator()
        navigator.openPalette()
        #expect(navigator.isPaletteVisible == true)
        navigator.go(to: .tool(.terminal))
        #expect(navigator.isPaletteVisible == false)
    }

    @Test func toggleAssistantFlips() {
        let navigator = Navigator()
        navigator.toggleAssistant()
        #expect(navigator.isAssistantVisible == true)
        navigator.toggleAssistant()
        #expect(navigator.isAssistantVisible == false)
    }

    @Test func destinationReportsToolAndScreenName() {
        #expect(Destination.board.tool == nil)
        #expect(Destination.board.screenName == "Board")
        #expect(Destination.tool(.admin).tool == .admin)
        #expect(Destination.tool(.admin).screenName == "LodiAdmin")
    }
}
