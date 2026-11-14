/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * Licence of the program it belongs to (klick).
 */

#include "jack_api.hh"

#include <dlfcn.h>
#include <vector>

namespace klickjack {

namespace {

template <typename F>
void resolve(void * handle, char const * name, F & out)
{
    void * symbol = dlsym(handle, name);
    if (!symbol) throw std::runtime_error(std::string("libjack has no ") + name);
    out = reinterpret_cast<F>(symbol);
}

JackApi open_api(std::string const & path)
{
    std::vector<std::string> candidates;
    if (!path.empty()) candidates.push_back(path);
    candidates.push_back("/usr/local/lib/libjack.dylib");
    candidates.push_back("/opt/homebrew/lib/libjack.dylib");
    candidates.push_back("/usr/local/lib/libjack.0.dylib");

    void * handle = nullptr;
    std::string reasons;
    for (auto const & c : candidates) {
        handle = dlopen(c.c_str(), RTLD_NOW | RTLD_LOCAL);
        if (handle) break;
        char const * e = dlerror();
        reasons += "\n  " + c + ": " + (e ? e : "?");
    }
    if (!handle) throw std::runtime_error("can't load libjack:" + reasons);

    JackApi a;
    resolve(handle, "jack_client_open", a.client_open);
    resolve(handle, "jack_client_close", a.client_close);
    resolve(handle, "jack_activate", a.activate);
    resolve(handle, "jack_deactivate", a.deactivate);
    resolve(handle, "jack_get_client_name", a.get_client_name);
    resolve(handle, "jack_get_sample_rate", a.get_sample_rate);
    resolve(handle, "jack_get_buffer_size", a.get_buffer_size);
    resolve(handle, "jack_set_process_callback", a.set_process_callback);
    resolve(handle, "jack_on_shutdown", a.on_shutdown);
    resolve(handle, "jack_port_register", a.port_register);
    resolve(handle, "jack_port_name", a.port_name);
    resolve(handle, "jack_port_get_buffer", a.port_get_buffer);
    resolve(handle, "jack_port_get_latency_range", a.port_get_latency_range);
    resolve(handle, "jack_port_disconnect", a.port_disconnect);
    resolve(handle, "jack_port_get_all_connections", a.port_get_all_connections);
    resolve(handle, "jack_port_by_name", a.port_by_name);
    resolve(handle, "jack_port_flags", a.port_flags);
    resolve(handle, "jack_connect", a.connect);
    resolve(handle, "jack_disconnect", a.disconnect);
    resolve(handle, "jack_get_ports", a.get_ports);
    resolve(handle, "jack_free", a.free);
    resolve(handle, "jack_transport_query", a.transport_query);
    resolve(handle, "jack_transport_start", a.transport_start);
    resolve(handle, "jack_transport_stop", a.transport_stop);
    resolve(handle, "jack_transport_locate", a.transport_locate);
    resolve(handle, "jack_transport_reposition", a.transport_reposition);
    resolve(handle, "jack_set_timebase_callback", a.set_timebase_callback);
    resolve(handle, "jack_release_timebase", a.release_timebase);
    resolve(handle, "jack_client_thread_id", a.client_thread_id);
    return a;
}

}

JackApi const & JackApi::load(std::string const & path)
{
    static JackApi const api = open_api(path);   // thread-safe, once
    return api;
}

}
