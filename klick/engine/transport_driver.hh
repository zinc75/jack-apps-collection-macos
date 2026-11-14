/*
 * The extension of the klick engine that ties what plays to the JACK transport: the metronome (or the tempo map) waits for the
 * transport to roll, plays while it rolls and stops with it; it can be the timebase master of the transport (bars, beats and tempo
 * for the other clients); and when another client is the timebase master, the simple metronome takes its tempo and meter.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 * Licence of the program it belongs to (klick).
 */

#ifndef KLICK_JACK_TRANSPORT_DRIVER_HH
#define KLICK_JACK_TRANSPORT_DRIVER_HH

#include "klick_engine_extension.hh"

#include <atomic>
#include <cstdint>

namespace klickjack {

class TransportDriver
  : public KlickEngineExtension
{
  public:
    explicit TransportDriver(AudioInterfaceTransport & transport);
    ~TransportDriver() override;

    /// Control thread. Read by the engine at each start.
    void set_follow(bool on) { _follow = on; }
    /// Becomes the timebase master (replacing the one there is), or gives it up. Throws when it cannot.
    void set_timebase_master(bool on);

    struct Info {
        int state;          // 0 not following (or stopped), 1 waiting for the transport, 2 rolling
        int external;       // 1 when another client is the timebase master
        float tempo;        // its tempo, in quarter notes per minute
        int beats, denom;   // its meter
    };
    Info info() const;

    // KlickEngineExtension
    void attached(KlickEngineControl & c) override { _ctl = &c; }
    bool gates_start() const override { return _follow; }
    void on_start(KlickEngineControl &, int mode) override;
    void on_stop(KlickEngineControl &) override;
    void before_block(KlickEngineControl &, nframes_t) override;
    void on_simple_beat(KlickEngineControl &, Metronome::BeatEvent const &) override;

  private:
    static constexpr double TPB = 1920.0;   // ticks per beat published to the transport (as klick does)

    void sync(bool mine);
    void restart_simple(bool external, position_t const & p);
    void timebase(position_t * p);

    AudioInterfaceTransport & _transport;
    KlickEngineControl * _ctl;
    bool _follow;                           // control thread: asked for
    std::atomic<bool> _timebase_on;
    bool _active;                           // audio thread: following, since the last start
    bool _simple_runs;                      // audio thread: the simple metronome plays
    bool _was_rolling;
    bool _external_was;                     // the tempo came from another timebase master at the previous block
    bool _restore_wanted;
    std::uint64_t _synced_for;              // block (frames + 1) the transport was last looked at
    std::uint64_t _cb_frames;               // block (frames + 1) our timebase callback ran for
    nframes_t _last_pos_frame, _last_block;
    std::atomic<int> _state;
    std::atomic<int> _ext_present, _ext_beats, _ext_denom;
    std::atomic<float> _ext_tempo;
    // BBT of the simple metronome, for the timebase callback
    bool _lb_valid; int _lb_bar, _lb_beat, _lb_beats, _lb_denom; float _lb_tempo; std::uint64_t _lb_frame;
    std::int64_t _tb_bar_start, _tb_next_bar_start;
};

}

#endif
