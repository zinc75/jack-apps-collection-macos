/*
 * Adapted from audio_interface_jack.cc of klick, Copyright (C) 2007-2013 Dominic Sacre <dominic.sacre@gmx.de>.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 * Licence of the program it belongs to (klick).
 */

#include "audio_interface_jack_dl.hh"

#include <cerrno>
#include <cstring>

namespace klickjack {

AudioInterfaceJackDl::AudioInterfaceJackDl(std::string const & name)
  : _api(JackApi::load()), _client(nullptr), _output_port(nullptr), _active(false), _shutdown(false)
{
    // JackNoStartServer: without it libjack starts a server by itself when there is none.
    jack_status_t status = static_cast<jack_status_t>(0);
    if ((_client = _api.client_open(name.c_str(), JackNoStartServer, &status)) == 0) {
        throw AudioError((status & (JackServerFailed | JackServerError)) ? "the JACK server is not running" : "can't connect to the JACK server");
    }

    _api.set_process_callback(_client, &process_callback_, static_cast<void*>(this));
    _api.on_shutdown(_client, &shutdown_callback_, static_cast<void*>(this));

    if ((_output_port = _api.port_register(_client, "out", JACK_DEFAULT_AUDIO_TYPE, JackPortIsOutput, 0)) == NULL) {
        throw AudioError("can't register output port");
    }

}

AudioInterfaceJackDl::~AudioInterfaceJackDl()
{
    if (_client) {
        if (_active) _api.deactivate(_client);
        _api.client_close(_client);
    }
}

void AudioInterfaceJackDl::start()
{
    if (_active) return;
    if (_api.activate(_client)) {
        throw AudioError("can't activate client");
    }
    _active = true;
}

void AudioInterfaceJackDl::stop()
{
    if (!_active) return;
    _api.deactivate(_client);
    _active = false;
}

std::string AudioInterfaceJackDl::client_name() const { return std::string(_api.get_client_name(_client)); }
pthread_t AudioInterfaceJackDl::client_thread() const { return _api.client_thread_id(_client); }
nframes_t AudioInterfaceJackDl::samplerate() const { return _api.get_sample_rate(_client); }
nframes_t AudioInterfaceJackDl::buffer_size() const { return _api.get_buffer_size(_client); }
bool AudioInterfaceJackDl::is_shutdown() const { return _shutdown; }
std::string AudioInterfaceJackDl::output_port_name() const { return std::string(_api.port_name(_output_port)); }

void AudioInterfaceJackDl::playback_latency(nframes_t & min, nframes_t & max) const
{
    jack_latency_range_t range;
    range.min = range.max = 0;
    _api.port_get_latency_range(_output_port, JackPlaybackLatency, &range);
    min = range.min; max = range.max;
}

void AudioInterfaceJackDl::set_timebase_callback(TimebaseCallback cb)
{
    if (cb) {
        if (_api.set_timebase_callback(_client, 0, &timebase_callback_, static_cast<void*>(this)) != 0) {
            throw AudioError("failed to become jack transport master");
        }
    } else {
        if (_timebase_cb) {
            _api.release_timebase(_client);
        }
    }
    _timebase_cb = cb;
}

void AudioInterfaceJackDl::connect(std::string const & port)
{
    int error = _api.connect(_client, _api.port_name(_output_port), port.c_str());
    if (error && error != EEXIST) {
        throw AudioError("can't connect " + output_port_name() + " to " + port);
    }
}

void AudioInterfaceJackDl::disconnect(std::string const & port)
{
    bool connected = false;
    for (auto const & p : input_ports()) if (p.name == port && p.connected) connected = true;
    if (!connected) return;     // already not connected
    int error = _api.disconnect(_client, _api.port_name(_output_port), port.c_str());
    if (error) {
        throw AudioError("can't disconnect " + output_port_name() + " from " + port);
    }
}

int AudioInterfaceJackDl::autoconnect()
{
    // the first two hardware outputs
    int connected = 0;
    char const **hw_ports = _api.get_ports(_client, NULL, JACK_DEFAULT_AUDIO_TYPE, JackPortIsPhysical | JackPortIsInput);
    if (hw_ports) {
        for (int n = 0; n < 2 && hw_ports[n] != NULL; ++n) {
            int error = _api.connect(_client, _api.port_name(_output_port), hw_ports[n]);
            if (!error || error == EEXIST) ++connected;
        }
        _api.free(hw_ports);
    }
    return connected;
}

std::vector<AudioInterfaceJackDl::PortInfo> AudioInterfaceJackDl::input_ports()
{
    std::vector<PortInfo> v;
    std::vector<std::string> connected;
    char const **links = _api.port_get_all_connections(_client, _output_port);
    if (links) {
        for (char const **p = links; *p; ++p) connected.push_back(*p);
        _api.free(links);
    }
    char const **ports = _api.get_ports(_client, NULL, JACK_DEFAULT_AUDIO_TYPE, JackPortIsInput);
    if (ports) {
        for (char const **p = ports; *p; ++p) {
            PortInfo info;
            info.name = *p;
            jack_port_t * port = _api.port_by_name(_client, *p);
            info.physical = port && (_api.port_flags(port) & JackPortIsPhysical);
            info.connected = false;
            for (auto const & c : connected) if (c == info.name) info.connected = true;
            v.push_back(info);
        }
        _api.free(ports);
    }
    return v;
}

void AudioInterfaceJackDl::disconnect_all()
{
    _api.port_disconnect(_client, _output_port);
}

std::vector<std::string> AudioInterfaceJackDl::available_ports()
{
    std::vector<std::string> v;
    char const **ports = _api.get_ports(_client, NULL, JACK_DEFAULT_AUDIO_TYPE, JackPortIsInput);
    if (ports) {
        for (char const **p = ports; *p; ++p) v.push_back(*p);
        _api.free(ports);
    }
    return v;
}

bool AudioInterfaceJackDl::transport_rolling() const
{
    return (_api.transport_query(_client, NULL) == JackTransportRolling);
}

position_t AudioInterfaceJackDl::position() const
{
    position_t pos;
    _api.transport_query(_client, &pos);
    return pos;
}

nframes_t AudioInterfaceJackDl::frame() const { return position().frame; }

bool AudioInterfaceJackDl::set_position(position_t const & pos)
{
    return (_api.transport_reposition(_client, const_cast<position_t*>(&pos)) == 0);
}

bool AudioInterfaceJackDl::set_frame(nframes_t frame)
{
    return (_api.transport_locate(_client, frame) == 0);
}

int AudioInterfaceJackDl::process_callback_(nframes_t nframes, void *arg)
{
    AudioInterfaceJackDl *this_ = static_cast<AudioInterfaceJackDl*>(arg);
    sample_t *buffer = (sample_t *)this_->_api.port_get_buffer(this_->_output_port, nframes);

    std::memset(buffer, 0, nframes * sizeof(sample_t));

    if (this_->_process_cb) {
        this_->_process_cb(buffer, nframes);
    }

    this_->process_mix(buffer, nframes);

    return 0;
}

void AudioInterfaceJackDl::timebase_callback_(jack_transport_state_t, nframes_t, position_t *pos, int, void *arg)
{
    AudioInterfaceJackDl *this_ = static_cast<AudioInterfaceJackDl*>(arg);
    if (this_->_timebase_cb) {
        this_->_timebase_cb(pos);
    }
}

void AudioInterfaceJackDl::shutdown_callback_(void *arg)
{
    static_cast<AudioInterfaceJackDl*>(arg)->_shutdown = true;
}

}
