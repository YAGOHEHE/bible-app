// swift-tools-version:5.9
import PackageDescription

// El target vive en la raíz de App/ para que "Resources/" (con bible.sqlite) sea
// un recurso del target sin copiar el fichero. Solo se compila Sources/BibliaApp.
let package = Package(
    name: "BibliaApp",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "6.29.3"),
    ],
    targets: [
        .executableTarget(
            name: "BibliaApp",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
            path: ".",
            exclude: ["Tests", "Package.swift", "Package.resolved"],
            sources: ["Sources/BibliaApp"],
            resources: [.copy("Resources")]
        ),
        .testTarget(
            name: "BibliaAppTests",
            dependencies: ["BibliaApp"],
            path: "Tests/BibliaAppTests"
        ),
    ]
)
