#include <arpa/inet.h>
#include <errno.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static pid_t server_pid = -1;

static void
cleanup_server(void)
{
    if (server_pid > 0) {
        kill(server_pid, SIGKILL);
        waitpid(server_pid, NULL, 0);
        server_pid = -1;
    }
}

static void
fail(const char *message)
{
    fprintf(stderr, "error: RSP smoke test: %s\n", message);
    cleanup_server();
    exit(EXIT_FAILURE);
}

static void
send_all(int socket_fd, const char *data, size_t size)
{
    while (size > 0) {
        ssize_t written = send(socket_fd, data, size, 0);
        if (written < 0) {
            if (errno == EINTR)
                continue;
            fail("send failed");
        }
        data += (size_t)written;
        size -= (size_t)written;
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
receive_packet(int socket_fd, char *payload, size_t capacity)
{
    unsigned int checksum = 0;
    size_t length = 0;
    unsigned char byte;

    for (;;) {
        ssize_t received = recv(socket_fd, &byte, 1, 0);
        if (received == 0)
            fail("server closed before a reply");
        if (received < 0) {
            if (errno == EINTR)
                continue;
            fail("receive failed or timed out");
        }
        if (byte == '$')
            break;
    }

    for (;;) {
        ssize_t received = recv(socket_fd, &byte, 1, 0);
        if (received <= 0)
            fail("truncated reply packet");
        if (byte == '#')
            break;
        if (length + 1 >= capacity)
            fail("reply packet is too large");
        payload[length++] = (char)byte;
        checksum = (checksum + byte) & 0xffU;
    }

    unsigned char digits[2];
    for (size_t index = 0; index < 2; ++index) {
        ssize_t received = recv(socket_fd, &digits[index], 1, 0);
        if (received <= 0)
            fail("truncated reply checksum");
    }
    int high = hex_value(digits[0]);
    int low = hex_value(digits[1]);
    if (high < 0 || low < 0 || checksum != (unsigned int)((high << 4) | low))
        fail("invalid reply checksum");

    payload[length] = '\0';
    send_all(socket_fd, "+", 1);
    return length;
}

int
main(int argc, char **argv)
{
    if (argc != 3) {
        fprintf(stderr, "usage: %s GDBSERVER TARGET\n", argv[0]);
        return EXIT_FAILURE;
    }
    if (atexit(cleanup_server) != 0)
        fail("could not register cleanup");

    int reserve_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (reserve_fd < 0)
        fail("could not create port-reservation socket");
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = 0;
    if (bind(reserve_fd, (struct sockaddr *)&address, sizeof(address)) != 0)
        fail("could not reserve a loopback port");
    socklen_t address_size = sizeof(address);
    if (getsockname(reserve_fd, (struct sockaddr *)&address, &address_size) != 0)
        fail("could not inspect reserved loopback port");
    unsigned int port = ntohs(address.sin_port);
    close(reserve_fd);

    char endpoint[64];
    if (snprintf(endpoint, sizeof(endpoint), "127.0.0.1:%u", port) >=
        (int)sizeof(endpoint))
        fail("loopback endpoint is too long");

    server_pid = fork();
    if (server_pid < 0)
        fail("fork failed");
    if (server_pid == 0) {
        execl(argv[1], argv[1], "--once", endpoint, argv[2], (char *)NULL);
        _exit(127);
    }

    int socket_fd = -1;
    struct timespec pause_time = { .tv_sec = 0, .tv_nsec = 50000000 };
    for (int attempt = 0; attempt < 200; ++attempt) {
        socket_fd = socket(AF_INET, SOCK_STREAM, 0);
        if (socket_fd < 0)
            fail("could not create client socket");
        if (connect(socket_fd, (struct sockaddr *)&address, sizeof(address)) == 0)
            break;
        close(socket_fd);
        socket_fd = -1;
        nanosleep(&pause_time, NULL);
    }
    if (socket_fd < 0)
        fail("could not connect to loopback gdbserver");

    struct timeval timeout = { .tv_sec = 30, .tv_usec = 0 };
    if (setsockopt(socket_fd, SOL_SOCKET, SO_RCVTIMEO, &timeout,
                   sizeof(timeout)) != 0 ||
        setsockopt(socket_fd, SOL_SOCKET, SO_SNDTIMEO, &timeout,
                   sizeof(timeout)) != 0)
        fail("could not set socket timeout");

    send_all(socket_fd, "$?#3f", 5);
    char reply[4096];
    size_t reply_length = receive_packet(socket_fd, reply, sizeof(reply));
    if (reply_length < 3 || (reply[0] != 'S' && reply[0] != 'T'))
        fail("server did not return a stop reply");

    send_all(socket_fd, "$k#6b", 5);
    shutdown(socket_fd, SHUT_RDWR);
    close(socket_fd);

    int status = 0;
    for (int attempt = 0; attempt < 400; ++attempt) {
        pid_t result = waitpid(server_pid, &status, WNOHANG);
        if (result == server_pid) {
            server_pid = -1;
            if (!WIFEXITED(status) || WEXITSTATUS(status) != 0)
                fail("gdbserver did not shut down cleanly");
            puts("validated loopback RSP stop reply and clean shutdown");
            return EXIT_SUCCESS;
        }
        if (result < 0)
            fail("waitpid failed");
        nanosleep(&pause_time, NULL);
    }

    fail("gdbserver did not exit after kill packet");
    return EXIT_FAILURE;
}
