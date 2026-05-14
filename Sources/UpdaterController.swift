import Sparkle

final class UpdaterController {
    private let updater: SPUStandardUpdaterController

    init() {
        updater = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        updater.checkForUpdates(nil)
    }
}
