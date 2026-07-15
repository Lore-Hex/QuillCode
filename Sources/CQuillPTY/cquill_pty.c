/* Request the X/Open definitions so glibc declares posix_openpt, grantpt,
 * unlockpt, and ptsname in <stdlib.h>. Must precede any system header. */
#ifndef _XOPEN_SOURCE
#define _XOPEN_SOURCE 600
#endif

#include "CQuillPTY.h"

#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <signal.h>
#include <errno.h>
#include <poll.h>

int cquill_pty_open(int *outMasterFD, int *outSlaveFD, char *slavePath, size_t slavePathLen) {
    if (outMasterFD == NULL || outSlaveFD == NULL || slavePath == NULL) {
        return -1;
    }

    int master = posix_openpt(O_RDWR | O_NOCTTY);
    if (master < 0) {
        return -1;
    }
    if (grantpt(master) != 0 || unlockpt(master) != 0) {
        close(master);
        return -1;
    }

    const char *name = ptsname(master);
    if (name == NULL) {
        close(master);
        return -1;
    }
    if (strlen(name) + 1 > slavePathLen) {
        close(master);
        return -1;
    }

    int slave = open(name, O_RDWR | O_NOCTTY);
    if (slave < 0) {
        close(master);
        return -1;
    }

    strncpy(slavePath, name, slavePathLen);
    slavePath[slavePathLen - 1] = '\0';
    *outMasterFD = master;
    *outSlaveFD = slave;
    return 0;
}

int cquill_pty_set_winsize(int masterFD, unsigned short rows, unsigned short columns) {
    struct winsize ws;
    ws.ws_row = rows;
    ws.ws_col = columns;
    ws.ws_xpixel = 0;
    ws.ws_ypixel = 0;
    if (ioctl(masterFD, TIOCSWINSZ, &ws) != 0) {
        return -1;
    }
    return 0;
}

int cquill_fd_isatty(int fileDescriptor) {
    if (fileDescriptor < 0) {
        return -1;
    }
    return isatty(fileDescriptor) == 1 ? 1 : 0;
}

ptrdiff_t cquill_fd_read(int fileDescriptor, void *buffer, size_t length) {
    ssize_t result;
    do {
        result = read(fileDescriptor, buffer, length);
    } while (result < 0 && errno == EINTR);
    return (ptrdiff_t)result;
}

int cquill_fd_wait_readable(int fileDescriptor, int timeoutMilliseconds) {
    if (fileDescriptor < 0 || timeoutMilliseconds < 0) {
        return -1;
    }
    struct pollfd descriptor;
    descriptor.fd = fileDescriptor;
    descriptor.events = POLLIN | POLLHUP;
    descriptor.revents = 0;

    int result;
    do {
        result = poll(&descriptor, 1, timeoutMilliseconds);
    } while (result < 0 && errno == EINTR);
    if (result <= 0) {
        return result;
    }
    return (descriptor.revents & (POLLIN | POLLHUP)) != 0 ? 1 : -1;
}

int cquill_signal_interrupt(void) {
    return SIGINT;
}

int cquill_signal_ignore(int signalNumber) {
    return signal(signalNumber, SIG_IGN) == SIG_ERR ? -1 : 0;
}

int cquill_signal_restore_default(int signalNumber) {
    return signal(signalNumber, SIG_DFL) == SIG_ERR ? -1 : 0;
}
