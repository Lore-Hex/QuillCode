#ifndef CQUILL_PTY_H
#define CQUILL_PTY_H

#include <stddef.h>

/// Opens a pseudo-terminal master/slave pair.
///
/// On success returns 0, sets `*outMasterFD` and `*outSlaveFD` to open file
/// descriptors for the master and slave ends, and writes the slave device path
/// into `slavePath` (NUL-terminated, up to `slavePathLen` bytes). On failure
/// returns -1 and leaves the output parameters untouched, closing any
/// descriptor it had already opened.
///
/// This lives in C because the POSIX pty helpers (`posix_openpt`, `grantpt`,
/// `unlockpt`, `ptsname`) are reliably available through the C standard library
/// headers on both Linux (glibc) and macOS, whereas Swift's imported Glibc
/// module does not surface them.
int cquill_pty_open(int *outMasterFD, int *outSlaveFD, char *slavePath, size_t slavePathLen);

/// Sets the terminal window size (rows x columns) on an open pty master via
/// `TIOCSWINSZ`. The change propagates to the slave so programs that query the
/// terminal size (e.g. `stty size`, ncurses TUIs) observe it. Returns 0 on
/// success, -1 on failure.
int cquill_pty_set_winsize(int masterFD, unsigned short rows, unsigned short columns);

/// Returns 1 when the descriptor is attached to a terminal, 0 when it is not, and -1 when the
/// descriptor cannot be inspected. Keeping this POSIX branch in the adapter target lets Swift
/// command code stay platform-neutral on macOS and Linux.
int cquill_fd_isatty(int fileDescriptor);

#endif /* CQUILL_PTY_H */
