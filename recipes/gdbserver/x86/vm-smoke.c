#include <errno.h>
#include <cpuid.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static pid_t server_pid = -1;
static pid_t target_pid = -1;

static void
power_off(void)
{
    sync();
    reboot(RB_POWER_OFF);
    reboot(RB_AUTOBOOT);
    _exit(1);
}

static void
cleanup_server(void)
{
    if (server_pid > 0) {
        kill(server_pid, SIGKILL);
        waitpid(server_pid, NULL, 0);
        server_pid = -1;
    }
    if (target_pid > 0) {
        kill(target_pid, SIGKILL);
        waitpid(target_pid, NULL, 0);
        target_pid = -1;
    }
}

static void
fail(const char *message)
{
    fprintf(stderr, "error: RSP smoke test: %s\n", message);
    cleanup_server();
    puts("STATIC_BINS_GDBSERVER_SMOKE_FAIL");
    fflush(NULL);
    power_off();
}

static void
close_pipe(int pipe_fds[2])
{
    close(pipe_fds[0]);
    close(pipe_fds[1]);
}

static void
write_all(int output_fd, const char *data, size_t size)
{
    while (size > 0) {
        ssize_t written = write(output_fd, data, size);
        if (written < 0) {
            if (errno == EINTR)
                continue;
            fail("write failed");
        }
        data += (size_t)written;
        size -= (size_t)written;
    }
}

static unsigned char
read_byte(int input_fd)
{
    struct pollfd poll_fd = {
        .fd = input_fd,
        .events = POLLIN,
        .revents = 0,
    };

    for (;;) {
        int result = poll(&poll_fd, 1, 30000);
        if (result < 0) {
            if (errno == EINTR)
                continue;
            fail("poll failed");
        }
        if (result == 0)
            fail("read timed out");
        if ((poll_fd.revents & (POLLIN | POLLHUP)) == 0)
            fail("protocol pipe failed");

        unsigned char byte;
        ssize_t received = read(input_fd, &byte, 1);
        if (received == 1)
            return byte;
        if (received == 0)
            fail("server closed before a complete reply");
        if (errno != EINTR)
            fail("read failed");
    }
}

static int
hex_value(unsigned char value)
{
    if (value >= '0' && value <= '9')
        return value - '0';
    if (value >= 'a' && value <= 'f')
        return value - 'a' + 10;
    if (value >= 'A' && value <= 'F')
        return value - 'A' + 10;
    return -1;
}

static size_t
receive_packet(int input_fd, int output_fd, char *payload, size_t capacity)
{
    unsigned int checksum = 0;
    size_t length = 0;
    unsigned char byte;

    do {
        byte = read_byte(input_fd);
    } while (byte != '$');

    for (;;) {
        byte = read_byte(input_fd);
        if (byte == '#')
            break;
        if (length + 1 >= capacity)
            fail("reply packet is too large");
        payload[length++] = (char)byte;
        checksum = (checksum + byte) & 0xffU;
    }

    unsigned char high_digit = read_byte(input_fd);
    unsigned char low_digit = read_byte(input_fd);
    int high = hex_value(high_digit);
    int low = hex_value(low_digit);
    if (high < 0 || low < 0 || checksum != (unsigned int)((high << 4) | low))
        fail("invalid reply checksum");

    payload[length] = '\0';
    write_all(output_fd, "+", 1);
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
    if (signal(SIGPIPE, SIG_IGN) == SIG_ERR)
        fail("could not ignore SIGPIPE");

    int to_server[2];
    int from_server[2];
    if (pipe(to_server) != 0 || pipe(from_server) != 0)
        fail("could not create protocol pipes");

    target_pid = fork();
    if (target_pid < 0)
        fail("target fork failed");
    if (target_pid == 0) {
        execl("/smoke-target", "/smoke-target", (char *)NULL);
        _exit(127);
    }

    char target_pid_text[32];
    if (snprintf(target_pid_text, sizeof(target_pid_text), "%ld",
                 (long)target_pid) >= (int)sizeof(target_pid_text))
        fail("target PID is too long");

    server_pid = fork();
    if (server_pid < 0)
        fail("fork failed");
    if (server_pid == 0) {
        if (dup2(to_server[0], STDIN_FILENO) < 0 ||
            dup2(from_server[1], STDOUT_FILENO) < 0)
            _exit(126);
        close_pipe(to_server);
        close_pipe(from_server);
        execl("/gdbserver", "/gdbserver", "--once", "--attach", "stdio",
              target_pid_text, (char *)NULL);
        _exit(127);
    }

    close(to_server[0]);
    close(from_server[1]);
    int output_fd = to_server[1];
    int input_fd = from_server[0];

    write_all(output_fd, "$?#3f", 5);
    char reply[4096];
    size_t reply_length = receive_packet(input_fd, output_fd, reply,
                                         sizeof(reply));
    if (reply_length < 3 || (reply[0] != 'S' && reply[0] != 'T'))
        fail("server did not return a stop reply");

    write_all(output_fd, "$k#6b", 5);
    close(output_fd);
    close(input_fd);

    int status = 0;
    struct timespec pause_time = { .tv_sec = 0, .tv_nsec = 50000000 };
    for (int attempt = 0; attempt < 400; ++attempt) {
        pid_t result = waitpid(server_pid, &status, WNOHANG);
        if (result == server_pid) {
            server_pid = -1;
            if (!WIFEXITED(status) || WEXITSTATUS(status) != 0)
                fail("gdbserver did not shut down cleanly");
            puts("validated full-system x86 RSP stop reply and clean shutdown");
            puts("STATIC_BINS_GDBSERVER_SMOKE_OK");
            fflush(NULL);
            power_off();
        }
        if (result < 0)
            fail("waitpid failed");
        nanosleep(&pause_time, NULL);
    }

    fail("gdbserver did not exit after kill packet");
    return EXIT_FAILURE;
}
