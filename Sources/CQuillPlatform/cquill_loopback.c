#include "CQuillPlatform.h"

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <netdb.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/stat.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

static int cquill_unix_address(const char *path, struct sockaddr_un *address) {
    if (path == NULL || address == NULL || path[0] != '/') {
        return -1;
    }
    size_t pathLength = strlen(path);
    if (pathLength == 0 || pathLength >= sizeof(address->sun_path)) {
        return -1;
    }
    memset(address, 0, sizeof(*address));
    address->sun_family = AF_UNIX;
    memcpy(address->sun_path, path, pathLength + 1);
    return 0;
}

static int cquill_unix_connect_address(const struct sockaddr_un *address) {
    int descriptor = socket(AF_UNIX, SOCK_STREAM, 0);
    if (descriptor < 0) {
        return -1;
    }

    int result;
    do {
        result = connect(descriptor, (const struct sockaddr *)address, sizeof(*address));
    } while (result != 0 && errno == EINTR);
    if (result != 0) {
        int connectionError = errno;
        close(descriptor);
        errno = connectionError;
        return -1;
    }

#ifdef SO_NOSIGPIPE
    int noSigPipe = 1;
    (void)setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, sizeof(noSigPipe));
#endif
    return descriptor;
}

static int cquill_unix_remove_stale_socket(
    const char *path,
    const struct sockaddr_un *address
) {
    struct stat first;
    if (lstat(path, &first) != 0) {
        return errno == ENOENT ? 0 : -1;
    }
    if (!S_ISSOCK(first.st_mode) || first.st_uid != geteuid()) {
        errno = EEXIST;
        return -1;
    }

    for (int attempt = 0; attempt < 4; attempt += 1) {
        int activeDescriptor = cquill_unix_connect_address(address);
        if (activeDescriptor >= 0) {
            close(activeDescriptor);
            errno = EADDRINUSE;
            return -1;
        }
        if (errno == ENOENT) {
            return 0;
        }
        if (errno != ECONNREFUSED) {
            return -1;
        }
        if (attempt < 3) {
            struct timespec delay;
            delay.tv_sec = 0;
            delay.tv_nsec = 20 * 1000 * 1000;
            while (nanosleep(&delay, &delay) != 0 && errno == EINTR) {}
        }
    }

    struct stat current;
    if (lstat(path, &current) != 0) {
        return errno == ENOENT ? 0 : -1;
    }
    if (!S_ISSOCK(current.st_mode) ||
        current.st_uid != geteuid() ||
        current.st_dev != first.st_dev ||
        current.st_ino != first.st_ino) {
        errno = EEXIST;
        return -1;
    }
    return unlink(path);
}

static int cquill_unix_unlink_identity(
    const char *path,
    uint64_t expectedDevice,
    uint64_t expectedInode
) {
    if (path == NULL) {
        return -1;
    }
    struct stat current;
    if (lstat(path, &current) != 0) {
        return errno == ENOENT ? 0 : -1;
    }
    if (!S_ISSOCK(current.st_mode) ||
        current.st_uid != geteuid() ||
        (uint64_t)current.st_dev != expectedDevice ||
        (uint64_t)current.st_ino != expectedInode) {
        errno = EEXIST;
        return -1;
    }
    return unlink(path);
}

static int cquill_bound_port(int descriptor, unsigned short *outBoundPort) {
    struct sockaddr_storage address;
    socklen_t addressLength = sizeof(address);
    if (getsockname(descriptor, (struct sockaddr *)&address, &addressLength) != 0) {
        return -1;
    }
    if (address.ss_family == AF_INET) {
        *outBoundPort = ntohs(((struct sockaddr_in *)&address)->sin_port);
        return 0;
    }
    if (address.ss_family == AF_INET6) {
        *outBoundPort = ntohs(((struct sockaddr_in6 *)&address)->sin6_port);
        return 0;
    }
    return -1;
}

int cquill_tcp_open(
    const char *numericHost,
    unsigned short requestedPort,
    unsigned short *outBoundPort
) {
    if (numericHost == NULL || numericHost[0] == '\0' || outBoundPort == NULL) {
        return -1;
    }

    char service[6];
    if (snprintf(service, sizeof(service), "%hu", requestedPort) < 0) {
        return -1;
    }
    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_flags = AI_NUMERICHOST | AI_PASSIVE;
    struct addrinfo *addresses = NULL;
    if (getaddrinfo(numericHost, service, &hints, &addresses) != 0) {
        return -1;
    }

    int descriptor = -1;
    for (struct addrinfo *candidate = addresses;
         candidate != NULL;
         candidate = candidate->ai_next) {
        descriptor = socket(candidate->ai_family, candidate->ai_socktype, candidate->ai_protocol);
        if (descriptor < 0) {
            continue;
        }
        int reuseAddress = 1;
        (void)setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_REUSEADDR,
            &reuseAddress,
            sizeof(reuseAddress)
        );
        if (bind(descriptor, candidate->ai_addr, candidate->ai_addrlen) == 0 &&
            listen(descriptor, 16) == 0 &&
            cquill_bound_port(descriptor, outBoundPort) == 0) {
            break;
        }
        close(descriptor);
        descriptor = -1;
    }
    freeaddrinfo(addresses);
    return descriptor;
}

int cquill_loopback_open(unsigned short requestedPort, unsigned short *outBoundPort) {
    return cquill_tcp_open("127.0.0.1", requestedPort, outBoundPort);
}

static void cquill_socket_disable_sigpipe(int descriptor) {
#ifdef SO_NOSIGPIPE
    int noSigPipe = 1;
    (void)setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, sizeof(noSigPipe));
#else
    (void)descriptor;
#endif
}

int cquill_tcp_connect(const char *numericHost, unsigned short port) {
    if (numericHost == NULL || numericHost[0] == '\0' || port == 0) {
        return -1;
    }

    char service[6];
    if (snprintf(service, sizeof(service), "%hu", port) < 0) {
        return -1;
    }
    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_flags = AI_NUMERICHOST;
    struct addrinfo *addresses = NULL;
    if (getaddrinfo(numericHost, service, &hints, &addresses) != 0) {
        return -1;
    }

    int descriptor = -1;
    for (struct addrinfo *candidate = addresses;
         candidate != NULL;
         candidate = candidate->ai_next) {
        descriptor = socket(candidate->ai_family, candidate->ai_socktype, candidate->ai_protocol);
        if (descriptor < 0) {
            continue;
        }
        int result;
        do {
            result = connect(descriptor, candidate->ai_addr, candidate->ai_addrlen);
        } while (result != 0 && errno == EINTR);
        if (result == 0) {
            break;
        }
        close(descriptor);
        descriptor = -1;
    }
    freeaddrinfo(addresses);
    if (descriptor >= 0) {
        cquill_socket_disable_sigpipe(descriptor);
    }
    return descriptor;
}

int cquill_loopback_connect(unsigned short port) {
    return cquill_tcp_connect("127.0.0.1", port);
}

int cquill_unix_open(
    const char *path,
    uint64_t *outDevice,
    uint64_t *outInode
) {
    if (outDevice == NULL || outInode == NULL) {
        return -1;
    }
    struct sockaddr_un address;
    if (cquill_unix_address(path, &address) != 0 ||
        cquill_unix_remove_stale_socket(path, &address) != 0) {
        return -1;
    }

    int descriptor = socket(AF_UNIX, SOCK_STREAM, 0);
    if (descriptor < 0) {
        return -1;
    }
    int flags = fcntl(descriptor, F_GETFL, 0);
    if (flags < 0 || fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) != 0) {
        int setupError = errno;
        close(descriptor);
        errno = setupError;
        return -1;
    }
    if (bind(descriptor, (struct sockaddr *)&address, sizeof(address)) != 0) {
        int bindError = errno;
        close(descriptor);
        errno = bindError;
        return -1;
    }

    struct stat bound;
    if (lstat(path, &bound) != 0) {
        int identityError = errno;
        close(descriptor);
        errno = identityError;
        return -1;
    }
    if (!S_ISSOCK(bound.st_mode) || bound.st_uid != geteuid()) {
        close(descriptor);
        errno = EEXIST;
        return -1;
    }
    if (chmod(path, S_IRUSR | S_IWUSR) != 0 || listen(descriptor, 16) != 0) {
        int setupError = errno;
        close(descriptor);
        (void)cquill_unix_unlink_identity(
            path,
            (uint64_t)bound.st_dev,
            (uint64_t)bound.st_ino
        );
        errno = setupError;
        return -1;
    }
    *outDevice = (uint64_t)bound.st_dev;
    *outInode = (uint64_t)bound.st_ino;
    return descriptor;
}

int cquill_unix_connect(const char *path) {
    struct sockaddr_un address;
    if (cquill_unix_address(path, &address) != 0) {
        return -1;
    }
    return cquill_unix_connect_address(&address);
}

int cquill_unix_unlink_if_same(
    const char *path,
    uint64_t expectedDevice,
    uint64_t expectedInode
) {
    return cquill_unix_unlink_identity(path, expectedDevice, expectedInode);
}

int cquill_loopback_accept(int serverDescriptor, int timeoutMilliseconds) {
    if (serverDescriptor < 0 || timeoutMilliseconds < 0) {
        return -1;
    }

    struct pollfd pollDescriptor;
    pollDescriptor.fd = serverDescriptor;
    pollDescriptor.events = POLLIN;
    pollDescriptor.revents = 0;

    int pollResult;
    do {
        pollResult = poll(&pollDescriptor, 1, timeoutMilliseconds);
    } while (pollResult < 0 && errno == EINTR);

    if (pollResult == 0) {
        return -2;
    }
    if (pollResult < 0 || (pollDescriptor.revents & POLLIN) == 0) {
        return -1;
    }

    int clientDescriptor;
    do {
        clientDescriptor = accept(serverDescriptor, NULL, NULL);
    } while (clientDescriptor < 0 && errno == EINTR);

    if (clientDescriptor >= 0) {
        int flags = fcntl(clientDescriptor, F_GETFL, 0);
        if (flags < 0 || fcntl(clientDescriptor, F_SETFL, flags & ~O_NONBLOCK) != 0) {
            int flagError = errno;
            close(clientDescriptor);
            errno = flagError;
            return -1;
        }
    }

#ifdef SO_NOSIGPIPE
    if (clientDescriptor >= 0) {
        int noSigPipe = 1;
        (void)setsockopt(
            clientDescriptor,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSigPipe,
            sizeof(noSigPipe)
        );
    }
#endif

    return clientDescriptor;
}

ptrdiff_t cquill_socket_receive(
    int descriptor,
    void *buffer,
    size_t length,
    int timeoutMilliseconds
) {
    if (descriptor < 0 || buffer == NULL || length == 0 || timeoutMilliseconds < 0) {
        return -1;
    }

    struct pollfd pollDescriptor;
    pollDescriptor.fd = descriptor;
    pollDescriptor.events = POLLIN;
    pollDescriptor.revents = 0;

    int pollResult;
    do {
        pollResult = poll(&pollDescriptor, 1, timeoutMilliseconds);
    } while (pollResult < 0 && errno == EINTR);
    if (pollResult == 0) {
        return -2;
    }
    if (pollResult < 0 ||
        (pollDescriptor.revents & (POLLIN | POLLHUP)) == 0) {
        return -1;
    }

    ssize_t result;
    do {
        result = recv(descriptor, buffer, length, 0);
    } while (result < 0 && errno == EINTR);
    return (ptrdiff_t)result;
}

int cquill_socket_send_all(int descriptor, const void *buffer, size_t length) {
    if (descriptor < 0 || (buffer == NULL && length > 0)) {
        return -1;
    }

    const unsigned char *bytes = (const unsigned char *)buffer;
    size_t offset = 0;
    while (offset < length) {
        ssize_t count;
        do {
#ifdef MSG_NOSIGNAL
            count = send(descriptor, bytes + offset, length - offset, MSG_NOSIGNAL);
#else
            count = send(descriptor, bytes + offset, length - offset, 0);
#endif
        } while (count < 0 && errno == EINTR);
        if (count <= 0) {
            return -1;
        }
        offset += (size_t)count;
    }
    return 0;
}

int cquill_socket_shutdown(int descriptor) {
    if (descriptor < 0) {
        return -1;
    }
    return shutdown(descriptor, SHUT_RDWR);
}

int cquill_descriptor_close(int descriptor) {
    if (descriptor < 0) {
        return -1;
    }
    return close(descriptor);
}
