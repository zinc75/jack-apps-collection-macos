/*
 * Test of the JACK backend of the klick engine on a JACK server of its own (JACK_DEFAULT_SERVER, run_jack_tests.sh starts it).
 * Usage: jack_backend_test <sounds dir> <expected sample rate> <expected block size> [--play <seconds>] | --no-server
 * Without a server (--no-server, with JACK_DEFAULT_SERVER naming one that does not run) the backend must refuse, and no server may be
 * started by the attempt. With --play the engine goes on playing for that long at the end, so that a recorder can be run beside it.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 * Licence of the program it belongs to (klick).
 */

#include "klick_jack.h"
#include "jack_api.hh"

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <thread>
#include <vector>

namespace {

int failures = 0;

#define CHECK(cond) do { if (!(cond)) { std::printf("FAIL line %d: %s\n", __LINE__, #cond); ++failures; } } while (0)

struct Port { bool physical; bool connected; std::string name; };

std::vector<Port> ports(KlickEngine * e)
{
    std::vector<char> buf(16384);
    size_t n = klick_jack_list_ports(e, buf.data(), buf.size());
    CHECK(n < buf.size());
    std::vector<Port> v;
    std::string text(buf.data());
    size_t pos = 0;
    while (pos < text.size()) {
        size_t end = text.find('\n', pos);
        if (end == std::string::npos) end = text.size();
        std::string line = text.substr(pos, end - pos);
        pos = end + 1;
        size_t t1 = line.find('\t'), t2 = line.find('\t', t1 + 1);
        if (t1 == std::string::npos || t2 == std::string::npos) continue;
        v.push_back({line[0] == 'p', line[t1 + 1] == '1', line.substr(t2 + 1)});
    }
    return v;
}

int connected_count(KlickEngine * e)
{
    int n = 0;
    for (auto const & p : ports(e)) if (p.connected) ++n;
    return n;
}


// A timebase master of the test: 90 beats per minute in 3/4, the bars and beats following the frame of the transport.
unsigned rate_for_master = 48000;
void master_callback(jack_transport_state_t, jack_nframes_t, jack_position_t * pos, int, void *)
{
    double beats = static_cast<double>(pos->frame) * 90.0 / (60.0 * rate_for_master);
    long whole = static_cast<long>(beats);
    pos->valid = JackPositionBBT;
    pos->bar = static_cast<int32_t>(whole / 3) + 1;
    pos->beat = static_cast<int32_t>(whole % 3) + 1;
    pos->tick = static_cast<int32_t>((beats - whole) * 1920.0);
    pos->bar_start_tick = static_cast<double>((whole / 3) * 3 * 1920);
    pos->beats_per_bar = 3.0f;
    pos->beat_type = 4.0f;
    pos->ticks_per_beat = 1920.0;
    pos->beats_per_minute = 90.0;
}

}

int main(int argc, char ** argv)
{
    char err[256] = "";
    char reason[256] = "";

    CHECK(klick_jack_available(reason, sizeof reason) == 1);

    if (argc > 1 && !std::strcmp(argv[1], "--no-server")) {
        KlickBackend b;
        CHECK(klick_jack_backend("Klick-test", &b, err, sizeof err) == 0);
        std::printf("without a server: %s\n", err);
        CHECK(std::string(err).find("not running") != std::string::npos);
        if (failures) { std::printf("%d failure(s)\n", failures); return 1; }
        std::printf("ok\n");
        return 0;
    }

    if (argc < 4) { std::fprintf(stderr, "usage: %s <sounds dir> <rate> <block> [--play <seconds>]\n", argv[0]); return 2; }
    std::string dir = argv[1];
    unsigned rate = static_cast<unsigned>(std::atoi(argv[2]));
    unsigned block = static_cast<unsigned>(std::atoi(argv[3]));
    double hold = (argc > 5 && !std::strcmp(argv[4], "--play")) ? std::atof(argv[5]) : 0.0;

    KlickBackend b;
    CHECK(klick_jack_backend("Klick-test", &b, err, sizeof err) == 1);
    if (failures) { std::printf("backend: %s\n", err); return 1; }
    KlickEngine * e = klick_engine_create_with_backend(&b, err, sizeof err);
    CHECK(e != NULL);
    if (!e) { std::printf("engine: %s\n", err); return 1; }

    CHECK(std::string(klick_engine_backend_id(e)) == "jack");
    CHECK(klick_jack_engine(e) == 1);
    CHECK(klick_engine_samplerate(e) == rate);
    CHECK(klick_jack_buffer_size(e) == block);
    CHECK(klick_engine_backend_is_shutdown(e) == 0);
    char name[128], port[128];
    klick_jack_client_name(e, name, sizeof name);
    klick_jack_port_name(e, port, sizeof port);
    std::printf("client %s, port %s, %u Hz, block %u\n", name, port, klick_engine_samplerate(e), klick_jack_buffer_size(e));
    CHECK(std::string(name).find("Klick-test") == 0);
    CHECK(std::string(port) == std::string(name) + ":out");

    // the ports of the server; the hardware ones are the system ones of the dummy driver
    std::vector<Port> before = ports(e);
    int physical = 0;
    for (auto const & p : before) { if (p.physical) ++physical; CHECK(!p.connected); }
    CHECK(physical == 2);
    CHECK(klick_jack_autoconnect(e) == 2);
    CHECK(connected_count(e) == 2);
    CHECK(klick_jack_autoconnect(e) == 2);              // again: nothing changes
    CHECK(connected_count(e) == 2);
    CHECK(klick_jack_disconnect(e, "system:playback_2", err, sizeof err) == 1);
    CHECK(connected_count(e) == 1);
    CHECK(klick_jack_disconnect(e, "system:playback_2", err, sizeof err) == 1);   // already not connected: fine
    CHECK(klick_jack_connect(e, "system:playback_2", err, sizeof err) == 1);
    CHECK(connected_count(e) == 2);
    CHECK(klick_jack_connect(e, "system:no_such_port", err, sizeof err) == 0);
    CHECK(err[0] != 0);
    uint32_t lmin = 99, lmax = 99;
    CHECK(klick_jack_playback_latency(e, &lmin, &lmax) == 1);
    std::printf("playback latency %u to %u frames\n", lmin, lmax);
    CHECK(klick_engine_output_latency(e) == lmax);

    // it plays: 120 BPM for a little over two seconds, the beats arrive with the audio thread of JACK
    CHECK(klick_engine_load_sound(e, (dir + "/square_emphasis.wav").c_str(), (dir + "/square_normal.wav").c_str(), 1, 1, 1, 1, err, sizeof err));
    CHECK(klick_engine_set_simple(e, 120.0f, 4, 4, "Xxxx", 0, 0, 0, err, sizeof err));
    klick_engine_set_volume(e, 0.5f);
    CHECK(klick_engine_start(e, KLICK_MODE_SIMPLE, err, sizeof err));
    std::this_thread::sleep_for(std::chrono::milliseconds(2300));
    KlickBeat beats[64];
    size_t n = klick_engine_poll_beats(e, beats, 64);
    std::printf("beat events in 2.3 s: %zu, position %llu frames\n", n, static_cast<unsigned long long>(klick_engine_position(e)));
    CHECK(n >= 4 && n <= 6);
    CHECK(klick_engine_position(e) > 2 * rate);
    for (size_t i = 0; i < n; ++i) CHECK(beats[i].beat == static_cast<int>(i % 4));
    if (n > 1) CHECK(beats[1].frame - beats[0].frame == rate / 2);
    CHECK(klick_engine_is_playing(e) == 1);
    CHECK(klick_engine_lost_beats(e) == 0);

    // A tempo map that follows the transport of JACK: silent while the transport is stopped, playing while it rolls, silent again
    // when it stops. Another client of the server rolls the transport.
    klick_engine_stop(e);
    n = klick_engine_poll_beats(e, beats, 64);   // what is left of the metronome
    KlickSection map = { "song", 16, 4, 4, 120.0f, 0.0f, "Xxxx", 1.0f, NULL, 0 };
    CHECK(klick_engine_set_map(e, &map, 1, 1.0f, err, sizeof err));
    klick_jack_set_transport_follow(e, 1);
    CHECK(klick_engine_start(e, KLICK_MODE_MAP, err, sizeof err));
    std::this_thread::sleep_for(std::chrono::milliseconds(800));
    CHECK(klick_engine_poll_beats(e, beats, 64) == 0);   // the transport is stopped
    {
        klickjack::JackApi const & api = klickjack::JackApi::load();
        jack_client_t * other = api.client_open("Klick-test-transport", JackNoStartServer, NULL);
        CHECK(other != NULL);
        if (other) {
            api.transport_start(other);
            std::this_thread::sleep_for(std::chrono::milliseconds(1700));
            size_t rolling = klick_engine_poll_beats(e, beats, 64);
            std::printf("beat events while the transport rolls: %zu\n", rolling);
            CHECK(rolling >= 2);
            CHECK(klick_engine_is_playing(e) == 1);
            api.transport_stop(other);
            std::this_thread::sleep_for(std::chrono::milliseconds(300));
            klick_engine_poll_beats(e, beats, 64);       // the last ones, scheduled before it stopped
            std::this_thread::sleep_for(std::chrono::milliseconds(1000));
            CHECK(klick_engine_poll_beats(e, beats, 64) == 0);   // stopped again
            api.client_close(other);
        }
    }
    klick_engine_stop(e);
    klick_jack_set_transport_follow(e, 0);

    // The simple metronome follows the transport as well: it waits, starts at its first beat when the transport rolls, and stops with it.
    {
        klickjack::JackApi const & api = klickjack::JackApi::load();
        KlickJackTransportInfo info;
        CHECK(klick_engine_set_simple(e, 120.0f, 4, 4, "Xxxx", 0, 0, 0, err, sizeof err));
        klick_jack_set_transport_follow(e, 1);
        CHECK(klick_engine_set_countin(e, 1, 4, 1.0f, err, sizeof err));   // (ignored while following)
        CHECK(klick_engine_start(e, KLICK_MODE_SIMPLE, err, sizeof err));
        std::this_thread::sleep_for(std::chrono::milliseconds(800));
        CHECK(klick_engine_poll_beats(e, beats, 64) == 0);   // the transport is stopped: the metronome waits
        klick_jack_transport_info(e, &info);
        CHECK(info.state == 1);
        CHECK(info.external == 0);
        jack_client_t * other = api.client_open("Klick-test-transport", JackNoStartServer, NULL);
        CHECK(other != NULL);
        if (other) {
            api.transport_locate(other, 0);
            api.transport_start(other);
            std::this_thread::sleep_for(std::chrono::milliseconds(1700));
            size_t rolling = klick_engine_poll_beats(e, beats, 64);
            std::printf("simple metronome, beat events while the transport rolls: %zu\n", rolling);
            CHECK(rolling >= 3 && rolling <= 4);
            if (rolling) CHECK(beats[0].beat == 0 && beats[0].count_in == 0);
            if (rolling > 1) CHECK(beats[1].frame - beats[0].frame == rate / 2);
            klick_jack_transport_info(e, &info);
            CHECK(info.state == 2);
            api.transport_stop(other);
            std::this_thread::sleep_for(std::chrono::milliseconds(300));
            klick_engine_poll_beats(e, beats, 64);
            klick_jack_transport_info(e, &info);
            CHECK(info.state == 1);
            std::this_thread::sleep_for(std::chrono::milliseconds(1000));
            CHECK(klick_engine_poll_beats(e, beats, 64) == 0);
            // rolls again: it starts again at its first beat
            api.transport_start(other);
            std::this_thread::sleep_for(std::chrono::milliseconds(700));
            rolling = klick_engine_poll_beats(e, beats, 64);
            CHECK(rolling >= 1);
            if (rolling) CHECK(beats[0].beat == 0);
            api.transport_stop(other);

            // Klick is the timebase master: the other clients read its tempo and meter, and the bars and beats while it plays
            CHECK(klick_engine_set_simple(e, 100.0f, 3, 4, "Xxx", 0, 0, 0, err, sizeof err));
            CHECK(klick_jack_set_timebase_master(e, 1, err, sizeof err));
            std::this_thread::sleep_for(std::chrono::milliseconds(300));
            api.transport_locate(other, 0);
            api.transport_start(other);
            std::this_thread::sleep_for(std::chrono::milliseconds(1300));
            jack_position_t pos;
            api.transport_query(other, &pos);
            std::printf("timebase master: valid %d, bar %d beat %d tick %d, %.1f bpm, %.0f/%.0f\n", static_cast<int>(pos.valid & JackPositionBBT),
                        pos.bar, pos.beat, pos.tick, pos.beats_per_minute, pos.beats_per_bar, pos.beat_type);
            CHECK(pos.valid & JackPositionBBT);
            CHECK(pos.beats_per_bar == 3.0f && pos.beat_type == 4.0f);
            CHECK(pos.beats_per_minute > 99.5 && pos.beats_per_minute < 100.5);
            CHECK(pos.bar == 1 && pos.beat >= 2 && pos.beat <= 3);   // 1.3 s at 100 BPM: the third beat
            api.transport_stop(other);
            // A tempo map that is the timebase master: nobody else is, and the engine must not take its own position for another client's
            klick_engine_stop(e);
            CHECK(klick_engine_set_map(e, &map, 1, 1.0f, err, sizeof err));
            CHECK(klick_engine_start(e, KLICK_MODE_MAP, err, sizeof err));
            api.transport_locate(other, 0);
            api.transport_start(other);
            std::this_thread::sleep_for(std::chrono::milliseconds(1000));
            klick_jack_transport_info(e, &info);
            CHECK(info.state == 2);
            CHECK(info.external == 0);
            api.transport_stop(other);
            CHECK(klick_jack_set_timebase_master(e, 0, err, sizeof err));
            klick_engine_stop(e);
            CHECK(klick_engine_set_simple(e, 100.0f, 3, 4, "Xxx", 0, 0, 0, err, sizeof err));
            CHECK(klick_engine_start(e, KLICK_MODE_SIMPLE, err, sizeof err));
            klick_engine_stop(e);
            klick_engine_poll_beats(e, beats, 64);

            // Another client is the timebase master (90 BPM in 3/4, the settings say 120 in 4/4): the metronome takes its tempo and meter,
            // and starts on the beat of the song.
            CHECK(klick_engine_set_simple(e, 120.0f, 4, 4, "Xxxx", 0, 0, 0, err, sizeof err));
            rate_for_master = rate;
            api.activate(other);
            CHECK(api.set_timebase_callback(other, 0, master_callback, NULL) == 0);
            CHECK(klick_engine_start(e, KLICK_MODE_SIMPLE, err, sizeof err));
            api.transport_locate(other, 0);
            std::this_thread::sleep_for(std::chrono::milliseconds(500));
            klick_jack_transport_info(e, &info);
            std::printf("external master: present %d, %.1f BPM, %d/%d\n", info.external, info.tempo, info.beats, info.denom);
            CHECK(info.external == 1);
            CHECK(info.tempo > 89.9f && info.tempo < 90.1f && info.beats == 3 && info.denom == 4);
            api.transport_start(other);
            std::this_thread::sleep_for(std::chrono::milliseconds(2500));
            rolling = klick_engine_poll_beats(e, beats, 64);
            std::printf("external master, beat events: %zu\n", rolling);
            CHECK(rolling >= 3);
            for (size_t i = 0; i < rolling; ++i) { CHECK(beats[i].beats == 3); CHECK(beats[i].beat == static_cast<int>(i % 3)); }
            if (rolling > 1) CHECK(std::llabs(static_cast<long long>(beats[1].frame) - static_cast<long long>(beats[0].frame) - 32000) <= 2);
            // relocated to the second beat of the second bar (a bar is 2 s): the next click is the third beat of that bar
            api.transport_locate(other, static_cast<jack_nframes_t>(rate * 2 + rate * 2 / 3 + 1000));
            std::this_thread::sleep_for(std::chrono::milliseconds(300));
            klick_engine_poll_beats(e, beats, 64);
            std::this_thread::sleep_for(std::chrono::milliseconds(1200));
            rolling = klick_engine_poll_beats(e, beats, 64);
            CHECK(rolling >= 1);
            if (rolling) CHECK(beats[0].beat == 2 || beats[0].beat == 0);
            api.transport_stop(other);
            klick_engine_stop(e);
            api.release_timebase(other);
            api.client_close(other);
        }
        klick_engine_set_countin(e, 0, 4, 0.0f, err, sizeof err);
    }
    klick_engine_stop(e);
    klick_jack_set_transport_follow(e, 0);

    if (hold > 0) {   // plays on for a recorder
        std::printf("playing on\n"); std::fflush(stdout);
        CHECK(klick_engine_set_simple(e, 120.0f, 4, 4, "Xxxx", 0, 0, 0, err, sizeof err));
        CHECK(klick_engine_start(e, KLICK_MODE_SIMPLE, err, sizeof err));
        std::this_thread::sleep_for(std::chrono::duration<double>(hold));
    }
    klick_engine_destroy(e);

    // not a JACK engine: the functions say so
    KlickEngine * off = klick_engine_create(1, 48000, err, sizeof err);
    CHECK(off != NULL);
    if (off) {
        CHECK(klick_jack_engine(off) == 0);
        CHECK(klick_jack_buffer_size(off) == 0);
        CHECK(klick_jack_autoconnect(off) == 0);
        CHECK(klick_jack_connect(off, "system:playback_1", err, sizeof err) == 0);
        klick_engine_destroy(off);
    }

    if (failures) { std::printf("%d failure(s)\n", failures); return 1; }
    std::printf("ok\n");
    return 0;
}
