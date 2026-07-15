import XCTest
@testable import AgentMascotApp

final class AvatarPresentationTests: XCTestCase {
    func testAvatarControlsAreMenuBarOnly() {
        XCTAssertTrue(RootViewPresentation.menuBar.showsAvatarControls)
        XCTAssertFalse(RootViewPresentation.settings.showsAvatarControls)
    }

    @MainActor
    func testChooseAvatarForwardsToInjectedAction() {
        let model = AppModel()
        var calls = 0
        model.chooseCustomAvatar = { calls += 1 }

        model.chooseAvatar()

        XCTAssertEqual(calls, 1)
    }
}
