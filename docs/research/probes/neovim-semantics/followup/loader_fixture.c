/* Synthetic LD_PRELOAD observer: positive control for pre-main execution only.
 * Never loaded into anything except these self-created tmux pane workloads. */
#define _GNU_SOURCE
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
__attribute__((constructor)) static void observe(void) {
    const char *path = getenv("PROBE_LOADER_MARK");
    if (!path) return;
    char cmd[512] = {0};
    int fd = open("/proc/self/cmdline", O_RDONLY | O_CLOEXEC);
    if (fd < 0) return;
    ssize_t n = read(fd, cmd, sizeof cmd - 1);
    close(fd);
    if (n <= 0) return;
    /* Skip executable argv[0], not arbitrary payload matching. */
    char *mode = memchr(cmd, 0, (size_t)n);
    if (!mode || mode + 1 >= cmd + n) return;
    mode++;
    const char *tag = !strcmp(mode, "launcher") ? "BOOTSTRAP\n" : "WORKLOAD\n";
    fd = open(path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC | O_NOFOLLOW, 0600);
    if (fd < 0) return;
    (void)write(fd, tag, strlen(tag));
    close(fd);
}
