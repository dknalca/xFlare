// swift-tools-version: 5.7
// SPDX-License-Identifier: GPL-3.0-only
import PackageDescription

// El grafo de dependencias de este fichero ES la arquitectura.
// Si un modulo no aparece en el array `dependencies` de otro, el compilador
// impide el `import`. No lo relajes por comodidad: es la unica barrera real
// que impide que la UI acabe metida en el hilo de audio.
// Ver docs/ARCHITECTURE.md seccion 2.

let package = Package(
    name: "xFlare",
    // macOS 11 Big Sur. NO subir sin ADR: la maquina de pruebas es un
    // MacBook Pro Intel de 2015 (tope Monterey). Ver docs/PLATFORM_SUPPORT.md.
    platforms: [.macOS(.v11)],
    products: [
        .library(name: "XFApp", targets: ["XFApp"]),
        // Cascaron ejecutable: abre una ventana y pinta la pantalla de inicio
        // maquetada. Sin logica. `swift run xFlare`. Las pantallas reales, en B11.
        .executable(name: "xFlare", targets: ["xFlare"]),
    ],
    dependencies: [
        // GRDB 6.x: GRDB 7 exige Swift 6 / Xcode 16 y aqui el techo es Xcode 14.2.
        .package(url: "https://github.com/groue/GRDB.swift.git", "6.0.0" ..< "7.0.0")
    ],
    targets: [

        // ---------- CAPA 0 · tiempo real (C) ----------
        .target(name: "CXFAudioCore",
                path: "Sources/CXFAudioCore",
                exclude: ["README.md"],
                cSettings: [.headerSearchPath("include")]),

        .target(name: "CXFTimecode",
                dependencies: ["CXFAudioCore"],
                path: "Sources/CXFTimecode",
                exclude: ["README.md"],
                // vendor/xwax/ : timecoder.c, lut.c y sus cabeceras, de xwax 1.10,
                // VENDORIZADOS INTACTOS (GPL-3.0-only, (c) Mark Hills). No se tocan;
                // si hace falta adaptar algo va en xf_timecode.c. Ver docs/TIMECODE.md.
                cSettings: [.headerSearchPath("include"),
                            .headerSearchPath("vendor/xwax")]),

        // Vocabulario compartido de muestras de entrada (Swift value types).
        // Esta en el fondo del grafo para que XFCapture (produce) y XFAnalysis
        // (consume) no tengan que verse entre si. Ver ADR-033.
        .target(name: "XFPrimitives", exclude: ["README.md"]),

        // ---------- CAPA 1 · dominio (Swift) ----------
        // `exclude: ["README.md"]` en los modulos que ya llevan su README de
        // sellado: SPM lo trataria como recurso sin declarar y avisa.
        .target(name: "XFClock", exclude: ["README.md"]),

        .target(name: "XFNotation",       dependencies: ["XFClock"], exclude: ["README.md"]),

        .target(name: "XFProfiles", exclude: ["README.md"]),

        .target(name: "XFCapture",        dependencies: ["XFPrimitives", "XFClock", "CXFTimecode", "XFProfiles"]),

        .target(name: "XFAnalysis",       dependencies: ["XFPrimitives", "XFNotation", "XFClock"],
                                          exclude: ["README.md"]),

        .target(name: "XFPersistence",    dependencies: ["XFNotation",
                                                         .product(name: "GRDB", package: "GRDB.swift")]),

        .target(name: "XFEngine",         dependencies: ["XFNotation", "XFCapture",
                                                         "XFAnalysis", "XFPersistence",
                                                         "CXFAudioCore"]),

        // ---------- CAPA 2 · presentacion ----------
        .target(name: "XFDesign", exclude: ["README.md"]),

        .target(name: "XFRender",         dependencies: ["XFDesign", "XFNotation"]),

        // ---------- CAPA 3 · app ----------
        .target(name: "XFApp",            dependencies: ["XFEngine", "XFRender", "XFDesign"]),

        // Ejecutable de andamiaje. Depende de XFApp solo para enlazar el grafo
        // entero y servir de prueba de humo. Su contenido (pantallas maquetadas)
        // se sustituye por la vista raiz real de XFApp en el bloque B11.
        .executableTarget(name: "xFlare", dependencies: ["XFApp"], path: "Sources/xFlare",
                          exclude: ["README.md"]),

        // ---------- utilidades de test ----------
        .target(name: "XFTestKit",        dependencies: ["XFCapture", "XFNotation"],
                                          resources: [.copy("Fixtures")]),

        // ---------- tests: uno por modulo ----------
        .testTarget(name: "CXFAudioCoreTests",  dependencies: ["CXFAudioCore"]),
        .testTarget(name: "XFPrimitivesTests",  dependencies: ["XFPrimitives"]),
        .testTarget(name: "CXFTimecodeTests",   dependencies: ["CXFTimecode", "XFTestKit"]),
        .testTarget(name: "XFClockTests",       dependencies: ["XFClock"]),
        .testTarget(name: "XFNotationTests",    dependencies: ["XFNotation", "XFTestKit"]),
        .testTarget(name: "XFProfilesTests",    dependencies: ["XFProfiles"]),
        .testTarget(name: "XFCaptureTests",     dependencies: ["XFCapture", "XFTestKit"]),
        .testTarget(name: "XFAnalysisTests",    dependencies: ["XFAnalysis", "XFTestKit"]),
        .testTarget(name: "XFPersistenceTests", dependencies: ["XFPersistence"]),
        .testTarget(name: "XFEngineTests",      dependencies: ["XFEngine", "XFTestKit"]),
        .testTarget(name: "XFDesignTests",      dependencies: ["XFDesign"]),
        .testTarget(name: "XFRenderTests",      dependencies: ["XFRender", "XFTestKit"]),
        .testTarget(name: "XFAppTests",         dependencies: ["XFApp"]),
    ]
)
