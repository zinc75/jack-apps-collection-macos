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

    if (hold > 0) std::this_thread::sleep_for(std::chrono::duration<double>(hold));
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
