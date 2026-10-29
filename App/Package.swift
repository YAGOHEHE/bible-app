// swift-tools-version:5.9
import PackageDescription

// Layout (see replica/CLASICA.md):
//   BibliaCore    library, Domain + Data, deployment target 10.13, NO Swift Concurrency. Owns Resources/ (bible.sqlite).
//   BibliaApp     SwiftUI executable (macOS 14). Needs macOS 14 APIs -> compiled with `-target ...macosx14.0`
//                 via unsafeFlags (SwiftPM has no per-target deployment target; the package minimum is 10.13).
//   BibliaClassic AppKit executable, 10.13+.
// All targets live under App/ (path ".") so "Resources/" is a resource of BibliaCore without copying the file.
// SwiftPM has no per-target deployment target. BibliaApp (SwiftUI/Observation, macOS 14) therefore overrides the
// compile target; BibliaCore and BibliaClassic use the package minimum (10.13 / the --triple given on the CLI).
#if arch(arm64)
let macOS14Target = "arm64-apple-macosx14.0"
#else
let macOS14Target = "x86_64-apple-macosx14.0"
#endif

let package = Package(
    name: "BibliaApp",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "BibliaCore", targets: ["BibliaCore"]),
        .executable(name: "BibliaApp", targets: ["BibliaApp"]),
        .executable(name: "BibliaClassic", targets: ["BibliaClassic"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "6.29.3"),
    ],
    targets: [
        // Bundled SQLite amalgamation (see Sources/CSQLite/README-SQLITE.txt). Named BundledSQLite to avoid clashing
        // with GRDB's own "CSQLite" system-library module.
        .target(
            name: "BundledSQLite",
            path: "Sources/CSQLite",
            exclude: ["README-SQLITE.txt"],
            sources: ["sqlite3.c"],
            publicHeadersPath: "include",
            cSettings: [
                .define("SQLITE_ENABLE_FTS5"),
                .define("SQLITE_ENABLE_SNAPSHOT"),
                .define("SQLITE_ENABLE_JSON1"),
                .define("SQLITE_THREADSAFE", to: "1"),
                .define("SQLITE_ENABLE_COLUMN_METADATA"),
                .define("SQLITE_ENABLE_MATH_FUNCTIONS"),
                .define("SQLITE_OMIT_LOAD_EXTENSION"),
                .define("SQLITE_DEFAULT_MEMSTATUS", to: "0"),
                .unsafeFlags(["-w"]),
            ]
        ),
        .target(
            name: "BibliaCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift"), "BundledSQLite"],
            path: ".",
            exclude: ["Tests", "Package.swift", "Package.resolved", "Sources/BibliaApp", "Sources/BibliaClassic", "Sources/CSQLite", "Icon"],
            sources: ["Sources/BibliaCore"],
            resources: [.copy("Resources")]
        ),
        .executableTarget(
            name: "BibliaApp",
            dependencies: ["BibliaCore", .product(name: "GRDB", package: "GRDB.swift")],
            path: "Sources/BibliaApp",
            swiftSettings: [.unsafeFlags(["-target", macOS14Target])]
        ),
        .executableTarget(
            name: "BibliaClassic",
            dependencies: ["BibliaCore", .product(name: "GRDB", package: "GRDB.swift")],
            path: "Sources/BibliaClassic",
            linkerSettings: [.unsafeFlags([
                // Frameworks/overlays auto-linked by GRDB & the SDK overlays that do not exist on 10.13 must be weak,
                // otherwise dyld refuses to launch. GRDB only touches them behind #available checks.
                "-Xlinker", "-weak_framework", "-Xlinker", "Combine",
                "-Xlinker", "-weak-lswift_Concurrency",
                "-Xlinker", "-weak-lswiftOSLog",
                "-Xlinker", "-weak-lswiftUniformTypeIdentifiers",
            ])]
        ),
        .testTarget(
            name: "BibliaAppTests",
            dependencies: ["BibliaApp", "BibliaCore"],
            path: "Tests/BibliaAppTests",
            swiftSettings: [.unsafeFlags(["-target", macOS14Target])]
        ),
        .testTarget(
            name: "BibliaCoreTests",
            dependencies: ["BibliaCore"],
            path: "Tests/BibliaCoreTests"
        ),
    ]
)
