// SPDX-License-Identifier: GPL-3.0-or-later
#ifndef ZITA_PTY_H
#define ZITA_PTY_H

#include <sys/types.h>

/// Runs `path` with `argv` and `envp` (both NULL terminated) in a new pseudo-terminal, as the leader of a session of its
/// own whose controlling terminal is the pseudo-terminal. Returns the process identifier, or -1 on failure; `*master_fd`
/// is then the master side, which the caller reads and which it must close.
///
/// Why a pseudo-terminal: zita-n2j prints its state with printf and never flushes, so into a pipe nothing arrives until the
/// buffer is full, which is never. Into a terminal the lines come at once. And when the master side is closed, even by a
/// crash of the application, the kernel sends SIGHUP to the program, which ends: no orphan is left on the JACK server.
pid_t zita_spawn_pty(const char *path, char *const argv[], char *const envp[], int *master_fd);

#endif
