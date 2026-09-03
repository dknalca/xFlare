// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import CoreVideo

/// Refresco real del display, para no pedirle 120 fps a un panel de 60 (ADR-024:
/// "no asumas 120; sincroniza con el refresco real: 60 en Intel, 120 si lo hay").
enum ScreenRefresh {

    /// fps del display que contiene `window` (o el principal). Redondeado a
    /// **60 / 120**; si no se puede saber, 60.
    static func fps(for window: NSWindow?) -> Int {
        guard let screen = window?.screen ?? NSScreen.main else { return 60 }
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let num = screen.deviceDescription[key] as? NSNumber else { return 60 }
        let displayID = CGDirectDisplayID(num.uint32Value)

        var hz = 0.0
        // 1) modo del display: fiable en pantallas externas; muchos paneles
        //    internos (el Retina del MBP 2015) devuelven 0 aqui.
        if let mode = CGDisplayCopyDisplayMode(displayID) {
            hz = mode.refreshRate
        }
        // 2) CVDisplayLink: si devuelve un periodo valido, gana (funciona en el
        //    panel interno). El periodo es segundos/refresco.
        var link: CVDisplayLink?
        if CVDisplayLinkCreateWithCGDisplay(displayID, &link) == kCVReturnSuccess, let link {
            let period = CVDisplayLinkGetActualOutputVideoRefreshPeriod(link)
            if period > 0 { hz = 1.0 / period }
        }

        return hz >= 90 ? 120 : 60
    }
}
