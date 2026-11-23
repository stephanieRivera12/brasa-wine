/* recv-tos.exe <tos>: sends one UDP datagram to itself on loopback with that TOS and IP_RECVTOS on,
 * the way Steam's networking sockets read ECN, and prints "tos=<n>" from the IP_TOS control
 * message, or "tos=none" when WSARecvMsg returned no such message. Exit 0 when one was received. */
#include <winsock2.h>
#include <ws2tcpip.h>
#include <mswsock.h>
#include <stdio.h>

#define PAYLOAD "brasa"
#define CONTROL_BYTES 256
#define EXIT_SOCKET_FAILED 2
#define EXIT_RECV_FAILED 3
#define EXIT_USAGE 4
#define NO_TOS (-1)

static LPFN_WSARECVMSG recvmsg_of( SOCKET s )
{
    GUID guid = WSAID_WSARECVMSG;
    LPFN_WSARECVMSG function = NULL;
    DWORD bytes;

    return WSAIoctl( s, SIO_GET_EXTENSION_FUNCTION_POINTER, &guid, sizeof(guid), &function,
                     sizeof(function), &bytes, NULL, NULL ) == 0 ? function : NULL;
}

/* Binds to loopback on a free port and turns on both TOS options. */
static SOCKET loopback_socket( struct sockaddr_in *address, DWORD tos )
{
    SOCKET s = socket( AF_INET, SOCK_DGRAM, IPPROTO_UDP );
    DWORD on = 1;
    int length = sizeof(*address);

    if (s == INVALID_SOCKET) return s;
    address->sin_family = AF_INET;
    address->sin_addr.s_addr = htonl( INADDR_LOOPBACK );
    address->sin_port = 0;
    if (bind( s, (struct sockaddr *)address, sizeof(*address) )
        || getsockname( s, (struct sockaddr *)address, &length )
        || setsockopt( s, IPPROTO_IP, IP_RECVTOS, (char *)&on, sizeof(on) )
        || setsockopt( s, IPPROTO_IP, IP_TOS, (char *)&tos, sizeof(tos) ))
    {
        closesocket( s );
        return INVALID_SOCKET;
    }
    return s;
}

/* Returns the TOS carried by the control messages, or NO_TOS when there is none. */
static int tos_of( WSAMSG *message )
{
    WSACMSGHDR *header;

    for (header = WSA_CMSG_FIRSTHDR( message ); header; header = WSA_CMSG_NXTHDR( message, header ))
        if (header->cmsg_level == IPPROTO_IP && header->cmsg_type == IP_TOS)
            return *(int *)WSA_CMSG_DATA( header );
    return NO_TOS;
}

/* Sends the payload to the socket's own address and stores the TOS it came back with. */
static int round_trip( SOCKET s, const struct sockaddr_in *address, int *tos )
{
    struct sockaddr_in from;
    char buffer[sizeof(PAYLOAD)], control[CONTROL_BYTES];
    WSABUF payload = { sizeof(buffer), buffer };
    WSAMSG message = { (struct sockaddr *)&from, sizeof(from), &payload, 1, { sizeof(control), control }, 0 };
    LPFN_WSARECVMSG receive = recvmsg_of( s );
    DWORD received;

    if (!receive) return EXIT_SOCKET_FAILED;
    if (sendto( s, PAYLOAD, sizeof(PAYLOAD), 0, (const struct sockaddr *)address, sizeof(*address) ) != sizeof(PAYLOAD))
        return EXIT_SOCKET_FAILED;
    if (receive( s, &message, &received, NULL, NULL )) return EXIT_RECV_FAILED;
    *tos = tos_of( &message );
    return 0;
}

static void print_tos( int tos )
{
    if (tos == NO_TOS) printf( "tos=none\n" );
    else printf( "tos=%d\n", tos );
}

int wmain( int argc, WCHAR **argv )
{
    WSADATA data;
    struct sockaddr_in address;
    SOCKET s;
    int status, tos = NO_TOS;

    if (argc != 2) return EXIT_USAGE;
    if (WSAStartup( MAKEWORD(2, 2), &data )) return EXIT_SOCKET_FAILED;
    s = loopback_socket( &address, (DWORD)_wtoi( argv[1] ) );
    status = s == INVALID_SOCKET ? EXIT_SOCKET_FAILED : round_trip( s, &address, &tos );
    if (!status) print_tos( tos );
    if (s != INVALID_SOCKET) closesocket( s );
    WSACleanup();
    return status;
}
