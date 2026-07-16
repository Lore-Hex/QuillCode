#ifndef CQUILL_PLATFORM_H
#define CQUILL_PLATFORM_H

#include <stddef.h>
#include <stdint.h>

/// Opens a TCP listener bound only to the IPv4 loopback interface. A requested port of zero asks
/// the operating system for an ephemeral port. Returns the descriptor on success and writes the
/// actual host-order port to `outBoundPort`; returns -1 on failure.
int cquill_loopback_open(unsigned short requestedPort, unsigned short *outBoundPort);

/// Opens a TCP listener on a numeric IPv4 or IPv6 address. Port zero requests an ephemeral port.
/// Returns the listener descriptor, or -1 on failure.
int cquill_tcp_open(
    const char *numericHost,
    unsigned short requestedPort,
    unsigned short *outBoundPort
);

/// Opens a TCP client connected to the IPv4 loopback listener on `port`. Returns the descriptor on
/// success or -1 on failure. Intended for platform-level integration tests and local adapters.
int cquill_loopback_connect(unsigned short port);

/// Connects to a numeric IPv4 or IPv6 address. Returns the connected descriptor, or -1.
int cquill_tcp_connect(const char *numericHost, unsigned short port);

/// Opens a private Unix-domain socket listener at an absolute filesystem path. A stale socket owned
/// by the current user is removed only after proving that no listener accepts connections. Existing
/// non-socket paths, symlinks, active listeners, and sockets owned by another user are preserved.
/// Returns the descriptor on success and writes the bound socket identity for race-safe cleanup.
int cquill_unix_open(
    const char *path,
    uint64_t *outDevice,
    uint64_t *outInode
);

/// Opens a client connection to an existing Unix-domain socket path. Returns the descriptor on
/// success or -1 on failure.
int cquill_unix_connect(const char *path);

/// Removes `path` only when it is still the same socket created by `cquill_unix_open` and is owned
/// by the current user. Returns 0 when removed or already absent, and -1 otherwise.
int cquill_unix_unlink_if_same(
    const char *path,
    uint64_t expectedDevice,
    uint64_t expectedInode
);

/// Waits up to `timeoutMilliseconds` for a client and accepts it. Returns a client descriptor,
/// -2 on timeout, or -1 on failure.
int cquill_loopback_accept(int serverDescriptor, int timeoutMilliseconds);

/// Waits up to `timeoutMilliseconds` and receives bytes from a connected socket. Returns the byte
/// count, -2 on timeout, or -1 on failure.
ptrdiff_t cquill_socket_receive(
    int descriptor,
    void *buffer,
    size_t length,
    int timeoutMilliseconds
);

/// Sends the complete byte buffer without raising SIGPIPE. Returns 0 on success or -1 on failure.
int cquill_socket_send_all(int descriptor, const void *buffer, size_t length);

/// Interrupts blocked socket operations without taking ownership of the descriptor.
int cquill_socket_shutdown(int descriptor);

/// Closes a descriptor.
int cquill_descriptor_close(int descriptor);

#endif /* CQUILL_PLATFORM_H */
