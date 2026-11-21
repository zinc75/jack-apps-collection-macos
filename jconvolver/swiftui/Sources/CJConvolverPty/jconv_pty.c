// SPDX-License-Identifier: GPL-3.0-or-later
#include "jconv_pty.h"

#include <fcntl.h>
#include <unistd.h>
#include <util.h>

pid_t jconv_spawn_pty(const char *path, char *const argv[], char *const envp[], int *master_fd)
{
    int fd = -1;
    pid_t pid = forkpty(&fd, NULL, NULL, NULL);
    if (pid < 0) return -1;
    if (pid == 0)
    {
        // The child: only what is safe between fork and exec.
        execve(path, argv, envp);
        _exit(127);
    }
    // Not inherited by the programs started later: they must not keep this one alive.
    fcntl(fd, F_SETFD, FD_CLOEXEC);
    *master_fd = fd;
    return pid;
}
