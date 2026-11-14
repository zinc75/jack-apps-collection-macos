/*
 * The JACK backend of klick, as in audio_interface_jack.hh of klick (Copyright (C) 2007-2013 Dominic Sacre), but every call to
 * libjack goes through JackApi (libjack loaded at run time), no server is ever started, and the client is activated by start()
 * (once the process callback is set), not by the constructor. One output port "out", the process callback of the metronome, the
 * transport of JACK.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 * Licence of the program it belongs to (klick).
 */

#ifndef KLICK_JACK_AUDIO_INTERFACE_JACK_DL_HH
#define KLICK_JACK_AUDIO_INTERFACE_JACK_DL_HH

#include "audio_interface.hh"
#include "jack_api.hh"

#include <string>
#include <vector>

namespace klickjack {

class AudioInterfaceJackDl
  : public AudioInterfaceTransport
{
  public:

    /// Connects to the JACK server (the one named by JACK_DEFAULT_SERVER, else the default one) as client `name`, without starting one:
    /// AudioError when there is none. Nothing is heard before start().
    explicit AudioInterfaceJackDl(std::string const & name);
    virtual ~AudioInterfaceJackDl();

    /// Activates the client: the process callback is called from now on. Set the callback of the metronome first.
    void start();
    void stop();

    virtual void set_timebase_callback(TimebaseCallback cb);

    std::string client_name() const;
    pthread_t client_thread() const;

    virtual nframes_t samplerate() const;
    nframes_t buffer_size() const;
    /// Latency of the output port towards the playback, in frames (the range JACK reports), once the connections are made.
    void playback_latency(nframes_t & min, nframes_t & max) const;
    virtual bool is_shutdown() const;

    std::string output_port_name() const;

    struct PortInfo {
        std::string name;
        bool physical;      // a port of the hardware
        bool connected;     // connected to our output
    };
    /// The input ports of the server, with what is connected to our output.
    std::vector<PortInfo> input_ports();
    /// Connects our output to `port`; an error if it fails (already connected is not one).
    void connect(std::string const & port);
    /// Disconnects our output from `port`.
    void disconnect(std::string const & port);
    /// Connects to the first two hardware outputs; returns how many were connected.
    int autoconnect();
    void disconnect_all();
    std::vector<std::string> available_ports();

    virtual bool transport_rolling() const;
    virtual position_t position() const;
    virtual nframes_t frame() const;
    virtual bool set_position(position_t const &);
    virtual bool set_frame(nframes_t);

  private:

    static int process_callback_(nframes_t, void *);
    static void timebase_callback_(jack_transport_state_t, nframes_t, position_t *, int, void *);
    static void shutdown_callback_(void *);

    JackApi const & _api;
    jack_client_t *_client;
    jack_port_t *_output_port;
    bool _active;

    volatile bool _shutdown;
};

}

#endif
