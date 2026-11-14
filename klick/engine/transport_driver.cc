/*
 * The extension of the klick engine that ties what plays to the JACK transport: see transport_driver.hh.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 * Licence of the program it belongs to (klick).
 */

#include "transport_driver.hh"

#include <algorithm>
#include <cmath>

namespace klickjack {

TransportDriver::TransportDriver(AudioInterfaceTransport & transport)
  : _transport(transport), _ctl(NULL), _follow(false), _timebase_on(false), _active(false), _simple_runs(true), _was_rolling(false),
    _external_was(false), _restore_wanted(false), _synced_for(0), _cb_frames(0), _last_pos_frame(0), _last_block(0),
    _state(0), _ext_present(0), _ext_beats(4), _ext_denom(4), _ext_tempo(0.0f),
    _lb_valid(false), _lb_bar(0), _lb_beat(0), _lb_beats(4), _lb_denom(4), _lb_tempo(120.0f), _lb_frame(0),
    _tb_bar_start(0), _tb_next_bar_start(0)
{
}

TransportDriver::~TransportDriver()
{
    if (_timebase_on.load()) {
        try { _transport.set_timebase_callback(AudioInterfaceTransport::TimebaseCallback()); } catch (...) { }
    }
}

void TransportDriver::set_timebase_master(bool on)
{
    try {
        _timebase_on.store(on, std::memory_order_relaxed);
        _transport.set_timebase_callback(on ? AudioInterfaceTransport::TimebaseCallback([this](position_t * p) { timebase(p); })
                                            : AudioInterfaceTransport::TimebaseCallback());
    } catch (...) {
        _timebase_on.store(false, std::memory_order_relaxed);
        throw;
    }
}

TransportDriver::Info TransportDriver::info() const
{
    Info i;
    i.state = _state.load(std::memory_order_relaxed);
    i.external = _ext_present.load(std::memory_order_relaxed);
    i.tempo = _ext_tempo.load(std::memory_order_relaxed);
    i.beats = _ext_beats.load(std::memory_order_relaxed);
    i.denom = _ext_denom.load(std::memory_order_relaxed);
    return i;
}

void TransportDriver::on_start(KlickEngineControl &, int)
{
    _active = _follow;
    _simple_runs = !_active;
    _was_rolling = false; _external_was = false; _restore_wanted = false;
    _lb_valid = false; _tb_bar_start = 0; _tb_next_bar_start = 0;
    _ext_present.store(0, std::memory_order_relaxed);
    _state.store(_active ? 1 : 0, std::memory_order_relaxed);
}

void TransportDriver::on_stop(KlickEngineControl &)
{
    _active = false; _simple_runs = true; _was_rolling = false; _external_was = false; _restore_wanted = false;
    _state.store(0, std::memory_order_relaxed);
    _ext_present.store(0, std::memory_order_relaxed);
}

void TransportDriver::before_block(KlickEngineControl &, nframes_t nframes)
{
    if (_active) sync(false);
    _last_block = nframes;
}

void TransportDriver::on_simple_beat(KlickEngineControl & c, Metronome::BeatEvent const & b)
{
    _lb_valid = true; _lb_bar = b.bar; _lb_beat = b.beat; _lb_beats = b.beats; _lb_denom = b.denom; _lb_tempo = b.tempo;
    _lb_frame = c.frames() + b.offset;
    if (b.beat == 0) {
        _tb_bar_start = _tb_next_bar_start;
        _tb_next_bar_start += static_cast<std::int64_t>(b.beats * TPB);
    }
}

// Starts the simple metronome again with the transport that has just started or moved. Another client that is the timebase master
// gives the position in bars and beats: the first click is the next beat of the song, not a first beat. Audio thread.
void TransportDriver::restart_simple(bool external, position_t const & p)
{
    MetronomeSimple & simple = _ctl->simple();
    simple.stop();
    simple.set_start_delay(0);
    simple.set_start_position(0, 0);
    if (external) {
        double beat_frames = _ctl->audio().samplerate() * 60.0 / p.beats_per_minute;   // (the beat of the master's meter)
        double done = p.tick / TPB;
        int bar = static_cast<int>(p.bar) - 1, beat = static_cast<int>(p.beat) - 1;
        nframes_t delay = 0;
        if (done > 0.0) {   // in the middle of a beat: the next one is the first click
            delay = static_cast<nframes_t>((1.0 - done) * beat_frames);
            if (++beat >= static_cast<int>(p.beats_per_bar)) { beat = 0; ++bar; }
        }
        simple.set_start_delay(delay);
        simple.set_start_position(std::max(bar, 0), std::max(beat, 0));
    }
    _tb_bar_start = 0; _tb_next_bar_start = 0; _lb_valid = false;
    simple.start();
    _simple_runs = true;
    _ctl->set_simple_waiting(false);
}

// Looks at the transport once per block: the simple metronome starts and stops with it, and takes the tempo and the meter of
// another timebase master. `mine`: called by our own timebase callback (we are the master, nobody else gives a tempo). Audio thread.
void TransportDriver::sync(bool mine)
{
    std::uint64_t now = _ctl->frames() + 1;
    if (_synced_for == now) return;
    _synced_for = now;
    int m = _ctl->mode();
    bool rolling = _transport.transport_rolling();
    position_t p = position_t();
    bool external = false;
    if (_cb_frames == now) mine = true;   // our callback has run for this block (a tempo map answers it without going through here)
    if (!mine && (!_timebase_on.load(std::memory_order_relaxed) || rolling)) {
        // (a master that is us would have been called before this block: if it was not, another one has taken the place)
        p = _transport.position();
        external = (p.valid & JackPositionBBT) && p.beats_per_minute > 0.0 && p.beat_type > 0.0f && p.beats_per_bar > 0.0f;
    }
    float tempo = external ? static_cast<float>(p.beats_per_minute * 4.0 / p.beat_type) : 0.0f;
    _ext_present.store(external ? 1 : 0, std::memory_order_relaxed);
    if (external) {
        _ext_tempo.store(tempo, std::memory_order_relaxed);
        _ext_beats.store(static_cast<int>(p.beats_per_bar), std::memory_order_relaxed);
        _ext_denom.store(static_cast<int>(p.beat_type), std::memory_order_relaxed);
    }
    if (m == KLICK_MODE_MAP) {   // the map has the position of the transport; the tempo is its own
        _state.store(rolling ? 2 : 1, std::memory_order_relaxed);
        return;
    }
    if (m != KLICK_MODE_SIMPLE) return;

    MetronomeSimple & simple = _ctl->simple();
    if (external) {
        if (std::fabs(tempo - simple.tempo()) > 0.001f) simple.set_tempo(tempo);
        int beats = static_cast<int>(p.beats_per_bar), denom = static_cast<int>(p.beat_type);
        if (beats != simple.beats() || denom != simple.denom()) simple.set_meter(beats, denom);
        _external_was = true;
    } else if (_external_was) {
        _external_was = false;
        _restore_wanted = true;
    }
    if (_restore_wanted && _ctl->reapply_settings()) _restore_wanted = false;

    bool moved = external && rolling && _was_rolling && p.frame != _last_pos_frame + _last_block;   // relocated while rolling
    if (rolling && (!_was_rolling || moved)) {
        restart_simple(external, p);
        _state.store(2, std::memory_order_relaxed);
    } else if (!rolling && _was_rolling) {
        simple.stop();
        _simple_runs = false;
        _ctl->set_simple_waiting(true);
        _state.store(1, std::memory_order_relaxed);
    }
    _was_rolling = rolling;
    _last_pos_frame = p.frame;
}

// Our timebase callback: the bars and beats of what plays, for the other clients. Audio thread, called before the block is processed.
void TransportDriver::timebase(position_t * p)
{
    _cb_frames = _ctl->frames() + 1;
    int m = _ctl->mode();
    if (m == KLICK_MODE_MAP && _ctl->map()) { _ctl->map()->timebase_callback(p); return; }
    if (m == KLICK_MODE_SIMPLE && _active) sync(true);
    MetronomeSimple & simple = _ctl->simple();
    p->valid = JackPositionBBT;
    p->ticks_per_beat = TPB;
    if (m == KLICK_MODE_SIMPLE && _simple_runs && _lb_valid && _lb_tempo > 0.0f && _lb_denom > 0) {
        double d = _ctl->audio().samplerate() * 240.0 / (_lb_tempo * _lb_denom);   // frames in the beat
        double done = std::max(0.0, std::min(0.999, (static_cast<double>(_ctl->frames()) - static_cast<double>(_lb_frame)) / d));
        p->bar = _lb_bar + 1; p->beat = _lb_beat + 1; p->tick = static_cast<std::int32_t>(done * TPB);
        p->bar_start_tick = static_cast<double>(_tb_bar_start);
        p->beats_per_bar = static_cast<float>(_lb_beats); p->beat_type = static_cast<float>(_lb_denom);
        p->beats_per_minute = _lb_tempo * _lb_denom / 4.0;
    } else {   // nothing plays yet: the start of the first bar, with the tempo of the settings
        p->bar = 1; p->beat = 1; p->tick = 0; p->bar_start_tick = 0.0;
        p->beats_per_bar = static_cast<float>(simple.beats()); p->beat_type = static_cast<float>(simple.denom());
        p->beats_per_minute = simple.tempo() * simple.denom() / 4.0;
    }
}

}
