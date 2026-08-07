#include <errno.h>
#include <cpuid.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

static const char expected_output[] = "static-bins-strace-marker\n";

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
    fprintf(stderr, "error: strace VM smoke test: %s\n", message);
    puts("STATIC_BINS_STRACE_SMOKE_FAIL");
    fflush(NULL);
    power_off();
}

static size_t
read_file(const char *path, char *buffer, size_t capacity)
{
    int fd = open(path, O_RDONLY);
    if (fd < 0)
        fail("could not open smoke output");

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
            fail("could not read smoke output");
        }
    }
    if (close(fd) != 0)
        fail("could not close smoke output");
    buffer[length] = '\0';
    return length;
}

int
main(void)
{
    unsigned int eax;
    unsigned int ebx;
    unsigned int ecx;
    unsigned int edx;
    if (!__get_cpuid(1, &eax, &ebx, &ecx, &edx) ||
        (edx & bit_CMOV) == 0 || (edx & bit_SSE2) == 0)
        fail("VM CPU does not expose CMOV and SSE2");

    if (mount("devtmpfs", "/dev", "devtmpfs", MS_NOSUID, NULL) != 0)
        fail("could not mount devtmpfs");
    if (mount("proc", "/proc", "proc", 0, NULL) != 0)
        fail("could not mount procfs");

    pid_t tracer_pid = fork();
    if (tracer_pid < 0)
        fail("could not fork tracer");
    if (tracer_pid == 0) {
        execl("/strace", "/strace", "-qq", "-o", "/trace.log",
              "-e", "trace=openat,write,exit_group", "/smoke-target",
              "/tracee.out", (char *) NULL);
        _exit(127);
    }

    int status = 0;
    if (waitpid(tracer_pid, &status, 0) != tracer_pid)
        fail("could not wait for tracer");
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0)
        fail("strace or its tracee did not exit successfully");

    char output[256];
    size_t output_size = read_file("/tracee.out", output, sizeof(output));
    if (output_size != sizeof(expected_output) - 1 ||
        memcmp(output, expected_output, sizeof(expected_output) - 1) != 0)
        fail("tracee output did not match the expected marker");

    char trace[16384];
    read_file("/trace.log", trace, sizeof(trace));
    if (strstr(trace, "openat(AT_FDCWD, \"/tracee.out\"") == NULL)
        fail("trace did not contain the expected openat syscall");
    if (strstr(trace, "write(") == NULL ||
        strstr(trace, "static-bins-strace-marker\\n") == NULL)
        fail("trace did not contain the expected write syscall and marker");
    if (strstr(trace, "exit_group(0)") == NULL)
        fail("trace did not contain the expected successful exit_group syscall");

    puts("validated full-system x86 direct-child ptrace decoding");
    puts("STATIC_BINS_STRACE_SMOKE_OK");
    fflush(NULL);
    power_off();
    return EXIT_FAILURE;
}
