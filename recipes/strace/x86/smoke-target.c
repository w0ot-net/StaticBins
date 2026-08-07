#include <fcntl.h>
#include <sys/syscall.h>
#include <unistd.h>

static const char marker[] = "static-bins-strace-marker\n";

int
main(int argc, char **argv)
{
    if (argc != 2)
        return 64;

    long fd = syscall(SYS_openat, AT_FDCWD, argv[1],
                      O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd < 0)
        return 65;
    if (syscall(SYS_write, fd, marker, sizeof(marker) - 1) !=
        (long) (sizeof(marker) - 1))
        return 66;
    syscall(SYS_close, fd);
    syscall(SYS_exit_group, 0);
    return 67;
}
