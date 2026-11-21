// SPDX-License-Identifier: GPL-3.0-or-later
#ifndef JCONV_PTY_H
#define JCONV_PTY_H

#include <sys/types.h>

/// Runs `path` with `argv` and `envp` (both NULL terminated) in a new pseudo-terminal, as the leader of a session of its
/// own whose controlling terminal is the pseudo-terminal. Returns the process identifier, or -1 on failure; `*master_fd`
/// is then the master side, which the caller reads and which it must close.
///
/// Why a pseudo-terminal: jconvolver and fconvolver write with printf and puts, which are buffered when the output is a
/// pipe, so the lines of the programs (a late computation thread, the reason of a stop) would arrive late or never. Into a
/// terminal they come at once. And when the master side is closed, even by a crash of the application, the kernel sends
/// SIGHUP to the program, which ends: no orphan is left on the JACK server.
pid_t jconv_spawn_pty(const char *path, char *const argv[], char *const envp[], int *master_fd);

#endif
