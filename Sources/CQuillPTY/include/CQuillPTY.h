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

#endif /* CQUILL_PTY_H */
