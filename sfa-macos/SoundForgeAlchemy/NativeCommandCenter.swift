import Foundation

enum PlaybackCommand: String {
    case playPause
    case previous
    case next
}

final class NativeCommandCenter {
    static let shared = NativeCommandCenter()

    static let selectSection = Notification.Name("SFA.NativeCommand.SelectSection")
    static let importFiles = Notification.Name("SFA.NativeCommand.ImportFiles")
    static let playback = Notification.Name("SFA.NativeCommand.Playback")
    static let runPipelineAction = Notification.Name("SFA.NativeCommand.RunPipelineAction")
    static let focusShowcaseChat = Notification.Name("SFA.NativeCommand.FocusShowcaseChat")

    private init() {}

    func select(_ section: NativeSection) {
        NotificationCenter.default.post(name: Self.selectSection, object: section.rawValue)
    }

    func importAudioFiles(paths: [String]) {
        NotificationCenter.default.post(name: Self.importFiles, object: paths)
    }

    func sendPlayback(_ command: PlaybackCommand) {
        NotificationCenter.default.post(name: Self.playback, object: command.rawValue)
    }

    func runPipeline(_ action: String) {
        NotificationCenter.default.post(name: Self.runPipelineAction, object: action)
    }

    func focusChat() {
        NotificationCenter.default.post(name: Self.focusShowcaseChat, object: nil)
    }
}
