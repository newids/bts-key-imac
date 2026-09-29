import AppKit
import ClassicHIDTransport

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var session: SessionController?
    private var statusMenu: StatusMenuController?
    private var onboarding: OnboardingWindowController?
    private let mainThreadWatch = MainThreadWatch()

    func applicationDidFinishLaunching(_ notification: Notification) {
        mainThreadWatch.start()
        let settings = Settings()
        let session = SessionController(settings: settings, transport: ClassicHIDTransport())
        self.session = session
        let onboarding = OnboardingWindowController(settings: settings, session: session)
        self.onboarding = onboarding
        let statusMenu = StatusMenuController(session: session, settings: settings)
        statusMenu.onShowOnboarding = { onboarding.show(at: $0) }
        self.statusMenu = statusMenu
        if settings.hasCompletedOnboarding {
            session.start()
        } else {
            // Guide first: the Bluetooth prompt is raised from its permission step, not at launch.
            onboarding.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        mainThreadWatch.stop()
        session?.prepareForTermination()
    }
}
