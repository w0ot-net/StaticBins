#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

static void
power_off(void)
{
    sync();
    reboot(RB_POWER_OFF);
    reboot(RB_AUTOBOOT);
    _exit(1);
}

static void
fail(const char *message)
{
    fprintf(stderr, "error: ltrace VM smoke test: %s\n", message);
    puts("STATIC_BINS_LTRACE_SMOKE_FAIL");
    fflush(NULL);
    power_off();
}

static size_t
read_file(const char *path, char *buffer, size_t capacity)
{
    int fd = open(path, O_RDONLY);
    if (fd < 0)
        fail("could not open trace output");

    size_t length = 0;
    while (length + 1 < capacity) {
        ssize_t result = read(fd, buffer + length, capacity - length - 1);
        if (result > 0) {
            length += (size_t) result;
            continue;
        }
        if (result == 0)
            break;
        if (errno != EINTR) {
            close(fd);
            fail("could not read trace output");
        }
    }
    if (close(fd) != 0)
        fail("could not close trace output");
    buffer[length] = '\0';
    return length;
}

int
main(void)
{
    if (mount("devtmpfs", "/dev", "devtmpfs", MS_NOSUID, NULL) != 0)
        fail("could not mount devtmpfs");
    if (mount("proc", "/proc", "proc", 0, NULL) != 0)
        fail("could not mount procfs");

    pid_t tracer_pid = fork();
    if (tracer_pid < 0)
        fail("could not fork tracer");
    if (tracer_pid == 0) {
        execl("/ltrace", "/ltrace", "-e", "puts", "-o", "/trace.log",
              "/smoke-target", (char *) NULL);
        _exit(127);
    }

    int status = 0;
    if (waitpid(tracer_pid, &status, 0) != tracer_pid)
        fail("could not wait for tracer");
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0)
        fail("ltrace or its tracee did not exit successfully");

    char trace[16384];
    read_file("/trace.log", trace, sizeof(trace));
    if (strstr(trace, "->puts(") == NULL)
        fail("trace did not contain the expected puts call");
    if (strstr(trace, "+++ exited (status 0) +++") == NULL)
        fail("trace did not record a successful child exit");

    puts("validated full-system direct-child musl library-call tracing");
    puts("STATIC_BINS_LTRACE_SMOKE_OK");
    fflush(NULL);
    power_off();
    return EXIT_FAILURE;
}
