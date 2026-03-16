import Foundation
import ServiceManagement

@MainActor
protocol LaunchAtLoginControlling {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

enum LaunchAtLoginControllerError: LocalizedError {
    case registrationFailed(underlying: any Error)
    case unregistrationFailed(underlying: any Error)

    var errorDescription: String? {
        switch self {
        case let .registrationFailed(underlying):
            return "Tempo could not register its login item. \(underlying.localizedDescription)"
        case let .unregistrationFailed(underlying):
            return "Tempo could not unregister its login item. \(underlying.localizedDescription)"
        }
    }
}

@MainActor
struct SMAppServiceLaunchAtLoginController: LaunchAtLoginControlling {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            if enabled {
                throw LaunchAtLoginControllerError.registrationFailed(underlying: error)
            }

            throw LaunchAtLoginControllerError.unregistrationFailed(underlying: error)
        }
    }
}
