/*
 * C interface to the JACK backend of the klick engine: see klick_jack.h.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 * Licence of the program it belongs to (klick).
 */

#include "klick_jack.h"

#include "audio_interface_jack_dl.hh"

#include <cstring>
#include <exception>
#include <string>

namespace {

using klickjack::AudioInterfaceJackDl;

void set_error(char * buf, size_t size, std::string const & message)
{
    if (buf && size) {
        std::strncpy(buf, message.c_str(), size - 1);
        buf[size - 1] = '\0';
    }
}

size_t copy_out(std::string const & text, char * buffer, size_t size)
{
    if (buffer && size) {
        std::strncpy(buffer, text.c_str(), size - 1);
        buffer[size - 1] = '\0';
    }
    return text.size();
}

// The AudioInterface is what the engine keeps (as a void pointer): back to the JACK interface.
AudioInterfaceJackDl * as_jack(void * audio)
{
    return static_cast<AudioInterfaceJackDl *>(static_cast<AudioInterface *>(audio));
}

AudioInterfaceJackDl * jack(KlickEngine const * e)
{
    char const * id = klick_engine_backend_id(e);
    return id && !std::strcmp(id, "jack") ? as_jack(klick_engine_backend_audio(e)) : NULL;
}

// The functions of the backend (klick_engine.h). start may throw: the engine catches it when it is made.
void jack_start(void * a) { as_jack(a)->start(); }
void jack_stop(void * a) { as_jack(a)->stop(); }
void jack_destroy(void * a) { delete as_jack(a); }
int jack_is_shutdown(void * a) { return as_jack(a)->is_shutdown() ? 1 : 0; }
uint32_t jack_latency(void * a)
{
    nframes_t lmin = 0, lmax = 0;
    as_jack(a)->playback_latency(lmin, lmax);
    return lmax;
}

}

extern "C" {

int klick_jack_available(char * reason, size_t reason_size)
{
    try {
        klickjack::JackApi::load();
        return 1;
    } catch (std::exception const & ex) {
        set_error(reason, reason_size, ex.what());
        return 0;
    }
}

int klick_jack_backend(char const * client_name, KlickBackend * backend, char * error, size_t error_size)
{
    try {
        AudioInterface * audio = new AudioInterfaceJackDl(client_name && *client_name ? client_name : "Klick");
        *backend = KlickBackend();
        backend->id = "jack";
        backend->audio = audio;     // as a pointer to the base class: that is what the engine casts it back to
        backend->realtime = 1;
        backend->start = jack_start;
        backend->stop = jack_stop;
        backend->destroy = jack_destroy;
        backend->output_latency = jack_latency;
        backend->is_shutdown = jack_is_shutdown;
        return 1;
    } catch (std::exception const & ex) {
        set_error(error, error_size, ex.what());
        return 0;
    }
}

int klick_jack_engine(KlickEngine const * e) { return jack(e) ? 1 : 0; }

size_t klick_jack_client_name(KlickEngine const * e, char * buffer, size_t size)
{
    AudioInterfaceJackDl * j = jack(e);
    return j ? copy_out(j->client_name(), buffer, size) : 0;
}

size_t klick_jack_port_name(KlickEngine const * e, char * buffer, size_t size)
{
    AudioInterfaceJackDl * j = jack(e);
    return j ? copy_out(j->output_port_name(), buffer, size) : 0;
}

uint32_t klick_jack_buffer_size(KlickEngine const * e)
{
    AudioInterfaceJackDl * j = jack(e);
    return j ? j->buffer_size() : 0;
}

int klick_jack_playback_latency(KlickEngine const * e, uint32_t * min_frames, uint32_t * max_frames)
{
    AudioInterfaceJackDl * j = jack(e);
    if (!j) return 0;
    nframes_t lmin = 0, lmax = 0;
    j->playback_latency(lmin, lmax);
    if (min_frames) *min_frames = lmin;
    if (max_frames) *max_frames = lmax;
    return 1;
}

size_t klick_jack_list_ports(KlickEngine const * e, char * buffer, size_t size)
{
    AudioInterfaceJackDl * j = jack(e);
    if (!j) return 0;
    try {
        std::string text;
        for (auto const & p : j->input_ports()) {
            text += p.physical ? "p\t" : "-\t";
            text += p.connected ? "1\t" : "0\t";
            text += p.name + "\n";
        }
        return copy_out(text, buffer, size);
    } catch (std::exception const &) {
        return 0;
    }
}

int klick_jack_connect(KlickEngine * e, char const * port, char * error, size_t error_size)
{
    AudioInterfaceJackDl * j = jack(e);
    if (!j) { set_error(error, error_size, "not a JACK engine"); return 0; }
    try {
        j->connect(port);
        return 1;
    } catch (std::exception const & ex) {
        set_error(error, error_size, ex.what());
        return 0;
    }
}

int klick_jack_disconnect(KlickEngine * e, char const * port, char * error, size_t error_size)
{
    AudioInterfaceJackDl * j = jack(e);
    if (!j) { set_error(error, error_size, "not a JACK engine"); return 0; }
    try {
        j->disconnect(port);
        return 1;
    } catch (std::exception const & ex) {
        set_error(error, error_size, ex.what());
        return 0;
    }
}

int klick_jack_autoconnect(KlickEngine * e)
{
    AudioInterfaceJackDl * j = jack(e);
    return j ? j->autoconnect() : 0;
}

}
