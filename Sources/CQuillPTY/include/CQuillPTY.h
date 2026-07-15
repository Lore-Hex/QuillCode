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

/// Reads up to `length` bytes from a descriptor, retrying interrupted system calls. Returns the
/// byte count, 0 at EOF, or -1 on failure. This keeps incremental POSIX pipe I/O behind the shared
/// macOS/Linux adapter instead of conditional platform imports in Swift command code.
ptrdiff_t cquill_fd_read(int fileDescriptor, void *buffer, size_t length);

/// Writes up to `length` bytes to a descriptor, retrying interrupted system calls. Returns the
/// byte count or -1 on failure. Callers repeat partial writes until their complete byte buffer has
/// been accepted.
ptrdiff_t cquill_fd_write(int fileDescriptor, const void *buffer, size_t length);

/// Waits until a descriptor can be read without blocking. Returns 1 when readable (including EOF),
/// 0 after `timeoutMilliseconds`, or -1 on failure. The bounded wait lets Swift cancellation stop an
/// incremental reader even while the peer keeps an otherwise idle pipe open.
int cquill_fd_wait_readable(int fileDescriptor, int timeoutMilliseconds);

/// Sends SIGKILL to a direct child process. Returns 0 on success (including an already-exited
/// process) and -1 for an invalid identifier or another signaling failure. This is used only after
/// a bounded graceful-termination window so an uncooperative standalone process cannot outlive its
/// app-server connection.
int cquill_process_force_kill(int processIdentifier);

/// Returns the platform's interrupt signal number (`SIGINT`). Keeping the POSIX constant in the C
/// adapter lets Swift command code install one signal source without importing Darwin or Glibc.
int cquill_signal_interrupt(void);

/// Changes `signalNumber` to the ignored or default disposition. These helpers are intentionally
/// narrow: QuillCode uses them only while a Dispatch signal source owns SIGINT delivery.
int cquill_signal_ignore(int signalNumber);
int cquill_signal_restore_default(int signalNumber);

#endif /* CQUILL_PTY_H */
