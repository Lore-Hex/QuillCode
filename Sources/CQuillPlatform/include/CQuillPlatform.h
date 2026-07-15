#ifndef CQUILL_PLATFORM_H
#define CQUILL_PLATFORM_H

#include <stddef.h>

/// Opens a TCP listener bound only to the IPv4 loopback interface. A requested port of zero asks
/// the operating system for an ephemeral port. Returns the descriptor on success and writes the
/// actual host-order port to `outBoundPort`; returns -1 on failure.
int cquill_loopback_open(unsigned short requestedPort, unsigned short *outBoundPort);

/// Opens a TCP client connected to the IPv4 loopback listener on `port`. Returns the descriptor on
/// success or -1 on failure. Intended for platform-level integration tests and local adapters.
int cquill_loopback_connect(unsigned short port);

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
