#include "CQuillPlatform.h"

#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <poll.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

int cquill_loopback_open(unsigned short requestedPort, unsigned short *outBoundPort) {
    if (outBoundPort == NULL) {
        return -1;
    }

    int descriptor = socket(AF_INET, SOCK_STREAM, 0);
    if (descriptor < 0) {
        return -1;
    }

    int reuseAddress = 1;
    (void)setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuseAddress, sizeof(reuseAddress));

    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = htons(requestedPort);

    if (bind(descriptor, (struct sockaddr *)&address, sizeof(address)) != 0 ||
        listen(descriptor, 4) != 0) {
        close(descriptor);
        return -1;
    }

    socklen_t addressLength = sizeof(address);
    if (getsockname(descriptor, (struct sockaddr *)&address, &addressLength) != 0) {
        close(descriptor);
        return -1;
    }

    *outBoundPort = ntohs(address.sin_port);
    return descriptor;
}

int cquill_loopback_connect(unsigned short port) {
    if (port == 0) {
        return -1;
    }

    int descriptor = socket(AF_INET, SOCK_STREAM, 0);
    if (descriptor < 0) {
        return -1;
    }

    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = htons(port);

    int result;
    do {
        result = connect(descriptor, (struct sockaddr *)&address, sizeof(address));
    } while (result != 0 && errno == EINTR);
    if (result != 0) {
        close(descriptor);
        return -1;
    }

#ifdef SO_NOSIGPIPE
    int noSigPipe = 1;
    (void)setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, sizeof(noSigPipe));
#endif

    return descriptor;
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
