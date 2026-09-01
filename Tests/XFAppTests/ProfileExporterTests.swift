// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFApp

/// B11.11 — exportar perfil (.conf válido según `tools/xf_profile.py`).
final class ProfileExporterTests: XCTestCase {

    private func audioReturnProfile() -> ExportableProfile {
        ExportableProfile(id: "Mi Mesa 2000", name: "Mi Mesa 2000", vendor: "Acme",
                          method: .audioReturn, cutInLeft: 0.06, cutInRight: 0.94,
                          hysteresis: 0.03, reverseDefault: true,
                          pilotFrequency: 19_500, pilotLevelDb: -40)
    }

    func testIdSeLimpiaAMinusculasSinEspacios() {
        XCTAssertEqual(audioReturnProfile().sanitizedId, "mi-mesa-2000")
    }

    func testConfDeAudioReturnEsValidoYTraeLasClaves() {
        let p = audioReturnProfile()
        XCTAssertTrue(ProfileExporter.isValid(p))
        let ini = ProfileExporter.iniText(p)
        XCTAssertTrue(ini.contains("[profile]"))
        XCTAssertTrue(ini.contains("id       = mi-mesa-2000"))
        XCTAssertTrue(ini.contains("verified = false"))
        XCTAssertTrue(ini.contains("method          = audio_return"))
        XCTAssertTrue(ini.contains("pilot.frequency = 19500"))
        XCTAssertTrue(ini.contains("cut_in.left     = 0.06"))
        XCTAssertTrue(ini.contains("cut_in.right    = 0.94"))
        XCTAssertTrue(ini.contains("reverse_default = true"))
    }

    func testMidiNecesitaSusCuatroClaves() {
        var p = ExportableProfile(id: "x", name: "X", vendor: "Y", method: .midi)
        XCTAssertFalse(ProfileExporter.isValid(p))
        XCTAssertTrue(ProfileExporter.validationErrors(p).contains { $0.contains("midi.cc") })

        p.midiChannel = 1; p.midiCC = 7; p.midiMin = 0; p.midiMax = 127
        XCTAssertTrue(ProfileExporter.isValid(p))
        XCTAssertTrue(ProfileExporter.iniText(p).contains("midi.cc         = 7"))
    }

    func testCutInFueraDeRangoYOrdenInvertido() {
        var p = audioReturnProfile()
        p.cutInLeft = 0.8; p.cutInRight = 0.2
        let errs = ProfileExporter.validationErrors(p)
        XCTAssertTrue(errs.contains("cut_in.left debe ser menor que cut_in.right"))

        p.cutInLeft = -0.1; p.cutInRight = 1.4
        let errs2 = ProfileExporter.validationErrors(p)
        XCTAssertTrue(errs2.contains("crossfader.cut_in.left fuera de 0..1"))
        XCTAssertTrue(errs2.contains("crossfader.cut_in.right fuera de 0..1"))
    }

    func testHidYNoneNoPidenClavesExtra() {
        for m in [ExportableProfile.Method.hid, .none] {
            let p = ExportableProfile(id: "x", name: "X", vendor: "Y", method: m)
            XCTAssertTrue(ProfileExporter.isValid(p), "method \(m.rawValue)")
        }
    }

    /// End-to-end: el .conf generado pasa el validador real `tools/xf_profile.py`.
    func testElConfPasaElValidadorPythonDeVerdad() throws {
        let python = "/usr/bin/env"
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let script = repoRoot.appendingPathComponent("tools/xf_profile.py")
        guard FileManager.default.fileExists(atPath: script.path) else {
            throw XCTSkip("no está tools/xf_profile.py")
        }

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("mi-mesa-2000.conf")
        try ProfileExporter.iniText(audioReturnProfile()).write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: python)
        proc.arguments = ["python3", script.path, "--check", tmp.path]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        do { try proc.run() } catch { throw XCTSkip("no se puede lanzar python3: \(error)") }
        proc.waitUntilExit()

        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(proc.terminationStatus, 0, "xf_profile.py rechazó el .conf:\n\(out)")
    }
}
