/* SPDX-License-Identifier: GPL-3.0-only */
/*
 * CXFTimecode — CAPA 0. Wrapper propio sobre xwax en modo relativo (ADR-004).
 *
 * Andamiaje (B0.1): sin logica todavia. En el bloque B5 se vendoriza xwax
 * (timecoder.c, lut.c) INTACTO en vendor/xwax/ y se anade su header search
 * path a Package.swift. Hasta entonces este target solo depende de CXFAudioCore.
 */
#ifndef XF_TIMECODE_H
#define XF_TIMECODE_H

/* Marcador de version del andamiaje. Se elimina al implementar B5. */
int xf_timecode_scaffolding_version(void);

#endif /* XF_TIMECODE_H */
