/* Disposable qualification fixture, not a Sess helper or a selected protocol. */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

static int same_dir(int fd, const char *path) {
    struct stat a, b;
    int named = open(path, O_PATH | O_DIRECTORY | O_CLOEXEC);
    if (named < 0) return 0;
    int ok = fstat(fd, &a) == 0 && fstat(named, &b) == 0 &&
        S_ISDIR(a.st_mode) && a.st_dev == b.st_dev && a.st_ino == b.st_ino &&
        faccessat(named, ".", X_OK, AT_EACCESS) == 0 && fchdir(fd) == 0;
    close(named);
    return ok;
}

int main(int argc, char **argv) {
    if (argc == 2 && !strcmp(argv[1], "constants")) {
        printf("%d\n", O_PATH | O_DIRECTORY | O_CLOEXEC);
        return 0;
    }
    if (argc == 3 && !strcmp(argv[1], "inherited")) {
        struct stat st;
        int ok = fstat(3, &st) == 0 && S_ISDIR(st.st_mode) && same_dir(3, argv[2]) &&
            !getenv("LD_PRELOAD") && !getenv("PROBE_SECRET");
        printf("%s\n", ok ? "PINNED" : "REJECTED");
        return ok ? 0 : 1;
    }
    return 2;
}
