// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFApp

/// Medidor de fps de la práctica (B7.2b). Puro: se le pasan los instantes de
/// fotograma y calcula media, peor caso y fotogramas perdidos.
final class FrameRateMeterTests: XCTestCase {

    /// Alimenta el medidor con `count` fotogramas espaciados `dt` segundos.
    private func run(_ m: inout FrameRateMeter, dt: Double, count: Int, from t0: Double = 1) {
        var t = t0
        for _ in 0..<count { m.tick(t); t += dt }
    }

    func testSesentaFpsEstables() {
        var m = FrameRateMeter()
        run(&m, dt: 1.0 / 60.0, count: 120)
        XCTAssertTrue(m.hasData)
        XCTAssertEqual(m.averageFPS, 60, accuracy: 0.5)
        XCTAssertEqual(m.droppedFrames(budgetMs: 1000.0 / 60.0 + 1), 0)
        XCTAssertLessThan(m.worstMs, 17.5)
    }

    func testCuentaLosFotogramasPerdidos() {
        var m = FrameRateMeter()
        // 20 buenos a 60, 1 tirón de 40 ms, 20 más buenos
        run(&m, dt: 1.0 / 60.0, count: 20)
        m.tick(1.0 + 20.0 / 60.0 + 0.040)          // un fotograma largo
        run(&m, dt: 1.0 / 60.0, count: 20, from: 1.0 + 20.0 / 60.0 + 0.040 + 1.0 / 60.0)
        XCTAssertEqual(m.droppedFrames(budgetMs: 20), 1, "solo el tirón de 40 ms")
        XCTAssertGreaterThan(m.worstMs, 39)
    }

    func testSaltosDeVsyncIgnoranElJitterDeBorde() {
        var m = FrameRateMeter()
        // fotogramas justo en el borde (17,5 ms): NO son saltos de vsync
        let n = 60
        run(&m, dt: 0.0175, count: n)
        XCTAssertEqual(m.missedVsyncs(targetFPS: 60), 0)
        // ahora sí, tres de 30 ms (saltaron un refresco)
        var t = 1.0 + Double(n - 1) * 0.0175
        for _ in 0..<3 { t += 0.030; m.tick(t) }
        XCTAssertEqual(m.missedVsyncs(targetFPS: 60), 3)
    }

    func testUnSaltoGrandeNoCuentaComoDrop() {
        var m = FrameRateMeter()
        run(&m, dt: 1.0 / 60.0, count: 30)
        m.tick(100)                                  // app en 2º plano ~1,5 min
        run(&m, dt: 1.0 / 60.0, count: 30, from: 100 + 1.0 / 60.0)
        // la ventana se reinicia en el salto: nada de drops de 98 s
        XCTAssertEqual(m.droppedFrames(budgetMs: 20), 0)
        XCTAssertEqual(m.averageFPS, 60, accuracy: 0.5)
    }

    func testVentanaAcotada() {
        var m = FrameRateMeter(window: 30)
        run(&m, dt: 1.0 / 30.0, count: 200)          // muchos, a 30 fps
        XCTAssertEqual(m.averageFPS, 30, accuracy: 0.5)
        // solo promedia los últimos 30 -> si mejora, converge rápido
        run(&m, dt: 1.0 / 120.0, count: 40, from: 500)
        XCTAssertEqual(m.averageFPS, 120, accuracy: 2)
    }

    func testSinDatosNoRevienta() {
        var m = FrameRateMeter()
        XCTAssertFalse(m.hasData)
        XCTAssertEqual(m.averageFPS, 0)
        XCTAssertEqual(m.worstMs, 0)
        XCTAssertEqual(m.summary(), "fps —")
        m.tick(1)                                    // un solo fotograma: aún nada
        XCTAssertFalse(m.hasData)
    }
}
