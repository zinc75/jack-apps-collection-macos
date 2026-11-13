/*
 * C interface to the JACK backend of the klick engine, for the Swift module that offers it. The backend is made here and given to
 * klick_engine_create_with_backend (klick_engine.h); the other functions work on the engine that was made with it. libjack is
 * loaded at run time (nothing is linked against it); no JACK server is ever started. Everything is called from the control thread.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 * Licence of the program it belongs to (klick).
 */

#ifndef KLICK_JACK_H
#define KLICK_JACK_H

#include <stddef.h>
#include <stdint.h>

#include "klick_engine.h"

#ifdef __cplusplus
extern "C" {
#endif

/* 1 when a libjack can be loaded; else 0 and the reason in 'reason'. Does not look for a server. */
int klick_jack_available(char *reason, size_t reason_size);

/* Fills 'backend' with a backend on the JACK server (the one JACK_DEFAULT_SERVER names, else the default one), as client
 * 'client_name' (JACK may rename it if the name is taken: see klick_jack_client_name). Returns 0 and writes to 'error' when libjack
 * cannot be loaded or there is no server ("the JACK server is not running"). Give the backend to klick_engine_create_with_backend,
 * which owns it from then on; if you do not, destroy nothing: it holds a client of the server, so create the engine at once. */
int klick_jack_backend(const char *client_name, KlickBackend *backend, char *error, size_t error_size);

/* 1 when the engine plays on the JACK backend. The functions below return 0 (or nothing) for any other engine. */
int klick_jack_engine(const KlickEngine *);

/* The name of the client in the server, the name of the output port, the size of the blocks of the server. Names are copied into
 * 'buffer' (cut if it is too small) and the length of the whole name is returned. */
size_t klick_jack_client_name(const KlickEngine *, char *buffer, size_t size);
size_t klick_jack_port_name(const KlickEngine *, char *buffer, size_t size);
uint32_t klick_jack_buffer_size(const KlickEngine *);
/* Latency of the output port towards the playback in frames, as JACK reports it once the output is connected (0 when it is not).
 * Returns 1 and writes both bounds; 0 for another engine. */
int klick_jack_playback_latency(const KlickEngine *, uint32_t *min_frames, uint32_t *max_frames);

/* The input ports of the server, one per line "<p or ->\t<1 or 0>\t<name>\n": p when it is a port of the hardware, 1 when the output
 * of the engine is connected to it. Copied into 'buffer' (cut if it is too small); returns the length of the whole list. */
size_t klick_jack_list_ports(const KlickEngine *, char *buffer, size_t size);

/* Connects the output to a port, or disconnects it; already connected, or already not, is fine. Returns 0 and writes to 'error'
 * when JACK refuses. */
int klick_jack_connect(KlickEngine *, const char *port, char *error, size_t error_size);
int klick_jack_disconnect(KlickEngine *, const char *port, char *error, size_t error_size);
/* Connects the output to the first two hardware outputs; returns how many are connected. */
int klick_jack_autoconnect(KlickEngine *);

#ifdef __cplusplus
}
#endif

#endif /* KLICK_JACK_H */
