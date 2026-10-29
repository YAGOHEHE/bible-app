import SwiftUI
import BibliaCore

// The macOS 15 `Translation` framework (re-exported by SwiftUI) clashes with BibliaCore.Translation.
typealias Translation = BibliaCore.Translation
