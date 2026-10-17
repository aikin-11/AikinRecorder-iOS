import SwiftUI
import UniformTypeIdentifiers

enum SystemPresenter {
    static func share(_ url: URL) {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        present(controller)
    }

    static func pickAudio(_ completion: @escaping ([URL]) -> Void) {
        let types = [UTType.mpeg4Audio, .mp3, .wav, .aiff, .audio, UTType(filenameExtension: "m4a"), UTType(filenameExtension: "aac")].compactMap { $0 }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        picker.allowsMultipleSelection = true
        let delegate = AudioPickerDelegate(completion: completion)
        picker.delegate = delegate
        objc_setAssociatedObject(picker, &AudioPickerDelegate.retainKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        present(picker)
    }

    private static func present(_ controller: UIViewController) {
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        if let popover = controller.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        top.present(controller, animated: true)
    }
}

private final class AudioPickerDelegate: NSObject, UIDocumentPickerDelegate {
    static var retainKey: UInt8 = 0
    let completion: ([URL]) -> Void
    init(completion: @escaping ([URL]) -> Void) { self.completion = completion }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { completion(urls) }
}
