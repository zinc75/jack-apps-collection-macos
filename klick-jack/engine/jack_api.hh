/*
 * libjack loaded at run time: the functions that klick uses, found by dlsym in the libjack of the system. Nothing is linked
 * against libjack, so the program starts (and says what is missing) on a Mac without JACK, and a libjack of any team can be
 * loaded (the application is signed with disable-library-validation, see the rules of the collection).
 * The types and constants come from the headers of JACK (/usr/local/include/jack); no function of them is called directly.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 * Licence of the program it belongs to (klick).
 */

#ifndef KLICK_JACK_API_HH
#define KLICK_JACK_API_HH

#include <jack/jack.h>
#include <jack/transport.h>
#include <string>
#include <stdexcept>

namespace klickjack {

struct JackApi {
    decltype(&::jack_client_open) client_open;
    decltype(&::jack_client_close) client_close;
    decltype(&::jack_activate) activate;
    decltype(&::jack_deactivate) deactivate;
    decltype(&::jack_get_client_name) get_client_name;
    decltype(&::jack_get_sample_rate) get_sample_rate;
    decltype(&::jack_get_buffer_size) get_buffer_size;
    decltype(&::jack_set_process_callback) set_process_callback;
    decltype(&::jack_on_shutdown) on_shutdown;
    decltype(&::jack_port_register) port_register;
    decltype(&::jack_port_name) port_name;
    decltype(&::jack_port_get_buffer) port_get_buffer;
    decltype(&::jack_port_get_latency_range) port_get_latency_range;
    decltype(&::jack_port_disconnect) port_disconnect;
    decltype(&::jack_port_get_all_connections) port_get_all_connections;
    decltype(&::jack_port_by_name) port_by_name;
    decltype(&::jack_port_flags) port_flags;
    decltype(&::jack_connect) connect;
    decltype(&::jack_disconnect) disconnect;
    decltype(&::jack_get_ports) get_ports;
    decltype(&::jack_free) free;
    decltype(&::jack_transport_query) transport_query;
    decltype(&::jack_transport_locate) transport_locate;
    decltype(&::jack_transport_reposition) transport_reposition;
    decltype(&::jack_set_timebase_callback) set_timebase_callback;
    decltype(&::jack_release_timebase) release_timebase;
    decltype(&::jack_client_thread_id) client_thread_id;

    /// Loads libjack from an absolute path (a bare name is not found without /usr/local/lib in the search path, and a hardened
    /// process refuses relative paths); `path` first if it is given, then the usual places. Throws std::runtime_error with the
    /// reason when no libjack is found or one of the functions is missing. The result lives as long as the process.
    static JackApi const & load(std::string const & path = std::string());
};

}

#endif
