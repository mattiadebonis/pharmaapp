import SwiftUI
import UIKit

struct ImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onImage: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onImage: (UIImage?) -> Void

        init(onImage: @escaping (UIImage?) -> Void) {
            self.onImage = onImage
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onImage(nil)
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = info[.originalImage] as? UIImage
            onImage(image)
        }
    }
}

struct SearchFieldAutoFocusInstaller: UIViewControllerRepresentable {
    let shouldFocus: Bool
    let onDidFocus: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDidFocus: onDidFocus)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.isHidden = true
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.onDidFocus = onDidFocus
        guard shouldFocus else { return }
        context.coordinator.requestFocus(from: uiViewController)
    }

    final class Coordinator {
        var onDidFocus: () -> Void
        private var isAttempting = false

        init(onDidFocus: @escaping () -> Void) {
            self.onDidFocus = onDidFocus
        }

        func requestFocus(from viewController: UIViewController) {
            guard !isAttempting else { return }
            isAttempting = true
            attemptFocus(from: viewController, attemptsRemaining: 12)
        }

        private func attemptFocus(from viewController: UIViewController, attemptsRemaining: Int) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                guard let searchController = viewController.findSearchController() else {
                    return self.retryIfNeeded(from: viewController, attemptsRemaining: attemptsRemaining - 1)
                }

                searchController.isActive = true
                let textField = searchController.searchBar.searchTextField
                if !textField.isFirstResponder {
                    textField.becomeFirstResponder()
                }

                if textField.isFirstResponder {
                    self.isAttempting = false
                    self.onDidFocus()
                } else {
                    self.retryIfNeeded(from: viewController, attemptsRemaining: attemptsRemaining - 1)
                }
            }
        }

        private func retryIfNeeded(from viewController: UIViewController, attemptsRemaining: Int) {
            guard attemptsRemaining > 0 else {
                isAttempting = false
                return
            }
            attemptFocus(from: viewController, attemptsRemaining: attemptsRemaining)
        }
    }
}

private extension UIViewController {
    func findSearchController() -> UISearchController? {
        var current: UIViewController? = self
        while let controller = current {
            if let searchController = controller.navigationItem.searchController {
                return searchController
            }
            current = controller.parent
        }

        if let nav = navigationController,
           let searchController = nav.topViewController?.navigationItem.searchController {
            return searchController
        }

        if let root = view.window?.rootViewController {
            return root.findSearchControllerInChildren()
        }

        return nil
    }

    func findSearchControllerInChildren() -> UISearchController? {
        if let searchController = navigationItem.searchController {
            return searchController
        }
        for child in children {
            if let searchController = child.findSearchControllerInChildren() {
                return searchController
            }
        }
        return nil
    }
}
