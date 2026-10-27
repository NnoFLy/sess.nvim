/* One-operation disposable C transport fixture. NOT a product helper/protocol.
 * Deliberately has no persistence, identity registry, recovery or retry logic. */
#define _GNU_SOURCE
#include <arpa/inet.h>
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
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

#define CAP (8U * 1024U * 1024U)
#define ENTRIES 65536U
#define HEADER 28U
static int64_t deadline;
static int64_t millis(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (int64_t)t.tv_sec * 1000 + t.tv_nsec / 1000000;
}
static int ready(int fd, short events) {
    for (;;) {
        int64_t left = deadline - millis();
        if (left <= 0) return 0;
        struct pollfd p = { fd, events, 0 };
        int n = poll(&p, 1, (int)left);
        if (n < 0 && errno == EINTR) continue;
        return n > 0;
    }
}
static int io(int fd, void *buf, size_t len, int writing) {
    unsigned char *p = buf;
    while (len) {
        if (!ready(fd, writing ? POLLOUT : POLLIN)) return 0;
        ssize_t n = writing ? write(fd, p, len) : read(fd, p, len);
        if (n < 0 && (errno == EINTR || errno == EAGAIN)) continue;
        if (n <= 0) return 0;
        p += n;
        len -= (size_t)n;
    }
    return 1;
}
static int end_of_request(int fd) {
    unsigned char extra;
    return ready(fd, POLLIN) && read(fd, &extra, 1) == 0;
}
static uint32_t num(const unsigned char *p) {
    uint32_t v;
    memcpy(&v, p, 4);
    return ntohl(v);
}
struct request {
    unsigned char *data;
    size_t size;
    uint32_t argc, envc, mode, op, flags;
    char *cwd, **argv, **env;
};
static char *string_at(struct request *r, size_t *offset) {
    if (*offset > r->size || r->size - *offset < 4) return NULL;
    uint32_t n = num(r->data + *offset);
    *offset += 4;
    if (n > r->size - *offset || memchr(r->data + *offset, 0, n)) return NULL;
    char *s = malloc((size_t)n + 1);
    if (!s) return NULL;
    memcpy(s, r->data + *offset, n);
    s[n] = 0;
    *offset += n;
    return s;
}
static int compare_names(const void *left, const void *right) {
    const char *a = *(const char * const *)left, *b = *(const char * const *)right;
    size_t x = strcspn(a, "="), y = strcspn(b, "=");
    int order = memcmp(a, b, x < y ? x : y);
    return order ? order : (x > y) - (x < y);
}
static int parse(struct request *r) {
    if (r->size < HEADER || r->size > CAP || memcmp(r->data, "SF01", 4) ||
        num(r->data + 4) != r->size) return 0;
    r->argc = num(r->data + 8); r->envc = num(r->data + 12);
    r->mode = num(r->data + 16); r->op = num(r->data + 20);
    r->flags = num(r->data + 24);
    if (!r->argc || r->argc > ENTRIES || r->envc > ENTRIES - r->argc ||
        r->mode > 2 || (r->flags & ~15U)) return 0;
    size_t at = HEADER;
    r->cwd = string_at(r, &at);
    if (!r->cwd || r->cwd[0] != '/') return 0;
    r->argv = calloc((size_t)r->argc + 1, sizeof(char *));
    r->env = calloc((size_t)r->envc + 4, sizeof(char *));
    if (!r->argv || !r->env) return 0;
    for (uint32_t i = 0; i < r->argc; i++)
        if (millis() >= deadline || !(r->argv[i] = string_at(r, &at))) return 0;
    if (r->argv[0][0] != '/') return 0; /* Editor-resolved path, never child PATH. */
    for (uint32_t i = 0; i < r->envc; i++) {
        r->env[i] = string_at(r, &at);
        if (!r->env[i] || millis() >= deadline) return 0;
        char *eq = strchr(r->env[i], '=');
        if (!eq || eq == r->env[i]) return 0;
        size_t len = (size_t)(eq - r->env[i]);
        if ((len == 4 && !memcmp(r->env[i], "TMUX", 4)) ||
            (len == 9 && !memcmp(r->env[i], "TMUX_PANE", 9))) return 0;
        if ((r->flags & 1) && len == 4 && !memcmp(r->env[i], "TERM", 4)) return 0;
    }
    qsort(r->env, r->envc, sizeof(char *), compare_names);
    for (uint32_t i = 1; i < r->envc; i++)
        if (!compare_names(&r->env[i - 1], &r->env[i])) return 0;
    return at == r->size && millis() < deadline;
}
static int input(struct request *r, int fd) {
    unsigned char head[HEADER];
    if (!io(fd, head, HEADER, 0)) return 0;
    uint32_t n = num(head + 4);
    if (n < HEADER || n > CAP) return 0;
    r->data = malloc(n);
    if (!r->data) return 0;
    r->size = n;
    memcpy(r->data, head, HEADER);
    return io(fd, r->data + HEADER, n - HEADER, 0) && parse(r);
}
/* Owned private parent and exact endpoint checks; no unlink-to-make-progress. */
static int endpoint(const char *path, int existing) {
    if (strlen(path) > 107 || path[0] != '/') return 0;
    char parent[108];
    strcpy(parent, path);
    char *slash = strrchr(parent, '/');
    if (!slash || slash == parent) return 0;
    *slash = 0;
    struct stat st;
    if (lstat(parent, &st) || !S_ISDIR(st.st_mode) || st.st_uid != getuid() ||
        (st.st_mode & 0777) != 0700) return 0;
    if (lstat(path, &st) == 0)
        return existing && S_ISSOCK(st.st_mode) && st.st_uid == getuid() &&
            (st.st_mode & 0777) == 0600;
    return !existing && errno == ENOENT;
}
static int peer(int fd, pid_t expected) {
    struct ucred c;
    socklen_t n = sizeof c;
    return !getsockopt(fd, SOL_SOCKET, SO_PEERCRED, &c, &n) && n == sizeof c &&
        c.uid == getuid() && (!expected || c.pid == expected);
}
static struct sockaddr_un address(const char *path) {
    struct sockaddr_un a = { .sun_family = AF_UNIX };
    memcpy(a.sun_path, path, strlen(path) + 1);
    return a;
}
static int status(int fd, uint32_t op, uint32_t tag, uint32_t error) {
    uint32_t s[3] = { htonl(op), htonl(tag), htonl(error) };
    return io(fd, s, sizeof s, 1);
}
static int send_dir(int fd, int dir) {
    char byte = 'D';
    struct iovec iov = { &byte, 1 };
    union { struct cmsghdr align; char bytes[CMSG_SPACE(sizeof(int))]; } control = {0};
    struct msghdr m = { .msg_iov = &iov, .msg_iovlen = 1,
        .msg_control = control.bytes, .msg_controllen = sizeof control.bytes };
    struct cmsghdr *c = CMSG_FIRSTHDR(&m);
    c->cmsg_level = SOL_SOCKET; c->cmsg_type = SCM_RIGHTS; c->cmsg_len = CMSG_LEN(sizeof(int));
    memcpy(CMSG_DATA(c), &dir, sizeof dir);
    return ready(fd, POLLOUT) && sendmsg(fd, &m, MSG_NOSIGNAL) == 1;
}
static int receive_dir(int fd) {
    char byte;
    struct iovec iov = { &byte, 1 };
    union { struct cmsghdr align; char bytes[CMSG_SPACE(sizeof(int) * 8)]; } control = {0};
    struct msghdr m = { .msg_iov = &iov, .msg_iovlen = 1,
        .msg_control = control.bytes, .msg_controllen = sizeof control.bytes };
    if (!ready(fd, POLLIN) || recvmsg(fd, &m, MSG_CMSG_CLOEXEC) != 1) return -1;
    int dir = -1, count = 0, bad = byte != 'D' || (m.msg_flags & (MSG_CTRUNC | MSG_TRUNC));
    for (struct cmsghdr *c = CMSG_FIRSTHDR(&m); c; c = CMSG_NXTHDR(&m, c)) {
        if (c->cmsg_level != SOL_SOCKET || c->cmsg_type != SCM_RIGHTS) { bad = 1; continue; }
        size_t n = (c->cmsg_len - CMSG_LEN(0)) / sizeof(int);
        for (size_t i = 0; i < n; i++) {
            int got;
            memcpy(&got, (char *)CMSG_DATA(c) + i * sizeof(int), sizeof got);
            if (!count) dir = got; else close(got);
            count++;
        }
    }
    struct stat st;
    if (bad || count != 1 || fstat(dir, &st) || !S_ISDIR(st.st_mode) ||
        !(fcntl(dir, F_GETFD) & FD_CLOEXEC)) {
        if (dir >= 0) close(dir);
        return -1;
    }
    return dir;
}
static int cwd_ok(int dir, const char *path) {
    struct stat a, b;
    int named = open(path, O_PATH | O_DIRECTORY | O_CLOEXEC);
    if (named < 0) return 0;
    int ok = !fstat(dir, &a) && !fstat(named, &b) && S_ISDIR(a.st_mode) &&
        a.st_dev == b.st_dev && a.st_ino == b.st_ino &&
        faccessat(named, ".", X_OK, AT_EACCESS) == 0 && fchdir(dir) == 0;
    close(named);
    return ok;
}
static int broker(const char *path, int dir) {
    struct request r = {0};
    if (!input(&r, 0) || !end_of_request(0) || !endpoint(path, 0)) { puts("REJECTED"); return 3; }
    struct stat st;
    if (fstat(dir, &st) || !S_ISDIR(st.st_mode)) return 3;
    int listener = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
    struct sockaddr_un a = address(path);
    if (listener < 0 || bind(listener, (void *)&a, sizeof a) || chmod(path, 0600) || listen(listener, 1)) return 3;
    puts("BOUND"); fflush(stdout);
    if (!ready(listener, POLLIN)) { puts("UNKNOWN"); return 2; }
    int fd = accept4(listener, NULL, NULL, SOCK_CLOEXEC | SOCK_NONBLOCK);
    uint32_t hello;
    if (fd < 0 || !peer(fd, 0) || !io(fd, &hello, 4, 0) || ntohl(hello) != r.op ||
        !send_dir(fd, dir) || !io(fd, r.data, r.size, 1) || shutdown(fd, SHUT_WR)) { puts("UNKNOWN"); return 2; }
    close(dir); close(listener);
    uint32_t s[3];
    if (!io(fd, s, sizeof s, 0) || ntohl(s[0]) != r.op) { puts("UNKNOWN"); return 2; }
    if (ntohl(s[1]) == 2) { printf("ERROR %u\n", ntohl(s[2])); return 1; }
    if (ntohl(s[1]) != 1 || ntohl(s[2])) { puts("UNKNOWN"); return 2; }
    /* A subsequent attributable exec error overrides launch acceptance.
     * EOF is NOT execution proof. Timeout/loss without completion is unknown. */
    if (!ready(fd, POLLIN)) { puts("UNKNOWN"); return 2; }
    ssize_t n = read(fd, s, sizeof s);
    if (n == 0) { puts("ACCEPTED_EXEC_UNVERIFIED"); return 0; }
    if (n > 0 && n < (ssize_t)sizeof s && io(fd, (char *)s + n, sizeof s - (size_t)n, 0)) n = sizeof s;
    if (n == sizeof s && ntohl(s[0]) == r.op && ntohl(s[1]) == 2) {
        printf("ERROR %u\n", ntohl(s[2])); return 1;
    }
    puts("UNKNOWN"); return 2;
}
static int launcher(const char *path, pid_t pid, uint32_t op) {
    if (!endpoint(path, 1)) return 3;
    int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
    struct sockaddr_un a = address(path);
    if (fd < 0 || connect(fd, (void *)&a, sizeof a) || !peer(fd, pid)) return 3;
    uint32_t hello = htonl(op);
    if (!io(fd, &hello, 4, 1)) return 3;
    int dir = receive_dir(fd);
    struct request r = {0};
    if (dir < 0 || !input(&r, fd) || !end_of_request(fd) || r.op != op) { status(fd, op, 2, EPROTO); return 1; }
    if (!cwd_ok(dir, r.cwd)) { status(fd, op, 2, ESTALE); return 1; }
    close(dir);
    const char *tmux = getenv("TMUX"), *pane = getenv("TMUX_PANE"), *term = getenv("TERM");
    if (!tmux || !pane || ((r.flags & 1) && !term) || getenv("PROBE_SECRET") || getenv("LD_PRELOAD")) {
        status(fd, op, 2, EPERM); return 1;
    }
    size_t n = r.envc;
    if (asprintf(&r.env[n++], "TMUX=%s", tmux) < 0 || asprintf(&r.env[n++], "TMUX_PANE=%s", pane) < 0) return 1;
    if ((r.flags & 1) && asprintf(&r.env[n++], "TERM=%s", term) < 0) return 1;
    r.env[n] = NULL;
    if (r.flags & 2) return 0; /* Deliberate loss before complete startup. */
    if (r.flags & 4) { while (millis() <= deadline + 200) poll(NULL, 0, 20); return 0; }
    if (r.flags & 8) { status(fd, op + 1, 1, 0); return 0; }
    if (!status(fd, op, 1, 0)) return 1;
    /* Absolute editor selection means execvpe cannot consult child PATH.
     * Qualified glibc execvpe supplies its native ENOEXEC /bin/sh fallback. */
    execvpe(r.argv[0], r.argv, r.env);
    int error = errno;
    status(fd, op, 2, (uint32_t)error);
    return 1;
}
static int eq(const char *key, const char *value) {
    const char *got = getenv(key);
    return got && !strcmp(got, value);
}
static int workload(int argc, char **argv) {
    if (argc < 3) return 2;
    int literal = argc == 10 && !strcmp(argv[3], "") && !strcmp(argv[4], ";") &&
        !strcmp(argv[5], "#{pane_id}") && !strcmp(argv[6], "#(false)") &&
        !strcmp(argv[7], "line\nnext") && !strcmp(argv[8], "quote'\\\"$") &&
        !strcmp(argv[9], "\xff");
    int env = eq("PROBE_SECRET", "synthetic-request-only") && !getenv("PROBE_DROP") &&
        eq("PROBE_EMPTY", "") && !getenv("PROBE_STALE") && eq("PWD", "captured-not-cwd") &&
        eq("NVIM", "synthetic-stale-address") && getenv("TMUX") && getenv("TMUX_PANE");
    int fds = 1;
    for (int i = 3; i < 1024; i++) if (fcntl(i, F_GETFD) >= 0) fds = 0;
    FILE *f = fopen(argv[2], "w");
    if (!f) return 2;
    fputs("{\"ready\":true}\n", f);
    fclose(f);
    char input[64];
    ssize_t n = ready(0, POLLIN) ? read(0, input, sizeof input) : -1;
    const char *expected = "synthetic-input\n";
    int input_ok = n == (ssize_t)strlen(expected) && !memcmp(input, expected, strlen(expected));
    f = fopen(argv[2], "w");
    if (!f) return 2;
    fprintf(f, "{\"literal\":%s,\"environment\":%s,\"pty\":%s,\"no_extra_fds\":%s,\"term_default\":%s,\"input\":%s}\n",
        literal ? "true" : "false", env ? "true" : "false",
        isatty(0) && isatty(1) && isatty(2) ? "true" : "false", fds ? "true" : "false",
        eq("TERM", "tmux-256color") ? "true" : "false", input_ok ? "true" : "false");
    fclose(f);
    return 0;
}
int main(int argc, char **argv) {
    signal(SIGPIPE, SIG_IGN);
    umask(077);
    deadline = millis() + 5000;
    if (argc == 2 && !strcmp(argv[1], "parse")) {
        struct request r = {0};
        int ok = input(&r, 0);
        if (ok) ok = end_of_request(0);
        puts(ok ? "VALID" : "REJECTED");
        return ok ? 0 : 3;
    }
    if (argc == 4 && !strcmp(argv[1], "broker")) return broker(argv[2], atoi(argv[3]));
    if (argc == 5 && !strcmp(argv[1], "launcher")) return launcher(argv[2], (pid_t)atoi(argv[3]), (uint32_t)strtoul(argv[4], NULL, 10));
    if (argc >= 3 && !strcmp(argv[1], "workload")) return workload(argc, argv);
    return 2;
}
