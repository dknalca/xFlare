/* SPDX-License-Identifier: GPL-3.0-only */
#include "xf_timecode.h"
#include "xf_audio_core.h" /* prueba el cableado del grafo: CXFTimecode -> CXFAudioCore */

/* Placeholder hasta el bloque B5. Devuelve la version del andamiaje de la capa 0. */
int xf_timecode_scaffolding_version(void) {
    return xf_audio_core_scaffolding_version();
}
