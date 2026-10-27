// Connect discovery's packet checks and relay (Shared/Connect) on the Mac. The checks run over packets
// made by hand, the bad ones included; the relay runs over loopback with a stand-in receiver and a
// stand-in for Spotify's socket, the system's sendto made to fail the way it does without the
// multicast entitlement.
#import <arpa/inet.h>
#import <errno.h>
#import <netinet/in.h>
#import <unistd.h>
#import "Shared/Connect/Connect.h"

static int failures;
#define CHECK(condition, what) do { if (!(condition)) { failures++; printf("FAIL %s\n", what); } else printf("ok   %s\n", what); } while (0)

#pragma mark - packets

typedef struct { uint8_t bytes[SGMDNSMaxLength + 64]; size_t length; } Packet;

static void put8(Packet *p, uint8_t value) { p->bytes[p->length++] = value; }
static void put16(Packet *p, uint16_t value) { put8(p, value >> 8); put8(p, value & 0xFF); }
static void header(Packet *p, uint16_t id, uint16_t flags, uint16_t qd, uint16_t an, uint16_t ns, uint16_t ar) {
    p->length = 0;
    put16(p, id); put16(p, flags); put16(p, qd); put16(p, an); put16(p, ns); put16(p, ar);
}
// Labels separated by '|', so a label may hold a dot; ends with the root.
static void name(Packet *p, const char *labels) {
    char copy[256];
    strlcpy(copy, labels, sizeof copy);
    char *rest = copy, *label;
    while ((label = strsep(&rest, "|"))) {
        put8(p, (uint8_t)strlen(label));
        memcpy(p->bytes + p->length, label, strlen(label));
        p->length += strlen(label);
    }
    put8(p, 0);
}
static void pointer(Packet *p, uint16_t to) { put16(p, 0xC000 | to); }
static void question(Packet *p, const char *labels) { name(p, labels); put16(p, 12); put16(p, 1); }
// A record's type, class, TTL and data length, after its owner name.
static void record(Packet *p, uint16_t type, uint16_t class, uint16_t dataLength) {
    put16(p, type); put16(p, class); put16(p, 0); put16(p, 120); put16(p, dataLength);
}

static const char *kConnect = "_spotify-connect|_tcp|local";

static Packet query(void) {
    Packet p;
    header(&p, 0, 0, 1, 0, 0, 0);
    question(&p, kConnect);
    return p;
}

// A legacy unicast answer: the question again, then a PTR from the service type to an instance whose
// name points back at the question's.
static Packet reply(uint16_t id) {
    Packet p;
    header(&p, id, 0x8400, 1, 1, 0, 0);
    question(&p, kConnect);
    pointer(&p, 12);
    record(&p, 12, 1, 2 + 1 + 7);
    name(&p, "Kitchen");
    p.length -= 1; // the instance label, then a pointer instead of the root
    pointer(&p, 12);
    return p;
}

static void checkQueries(void) {
    Packet p = query();
    CHECK(SGMDNSIsConnectQuery(p.bytes, p.length), "query: the service type");
    header(&p, 0, 0, 1, 0, 0, 0); question(&p, "_living._sub|_spotify-connect|_tcp|local");
    CHECK(SGMDNSIsConnectQuery(p.bytes, p.length), "query: a subtype");
    header(&p, 0, 0, 1, 0, 0, 0); question(&p, "_SPOTIFY-CONNECT|_TCP|LOCAL");
    CHECK(SGMDNSIsConnectQuery(p.bytes, p.length), "query: upper case");
    header(&p, 0, 0, 2, 0, 0, 0); question(&p, "_googlecast|_tcp|local"); question(&p, kConnect);
    CHECK(SGMDNSIsConnectQuery(p.bytes, p.length), "query: Connect second of two");
    header(&p, 0, 0, 2, 0, 0, 0); question(&p, "a|_tcp|local"); put8(&p, 16); memcpy(p.bytes + p.length, "_spotify-connect", 16); p.length += 16; pointer(&p, 14); put16(&p, 12); put16(&p, 1);
    CHECK(SGMDNSIsConnectQuery(p.bytes, p.length), "query: a compressed name");
    header(&p, 0, 0, 1, 0, 0, 0); question(&p, "_googlecast|_tcp|local");
    CHECK(!SGMDNSIsConnectQuery(p.bytes, p.length), "query: Cast only is not relayed");
    header(&p, 0, 0, 1, 0, 0, 0); question(&p, "x_spotify-connect|_tcp|local");
    CHECK(!SGMDNSIsConnectQuery(p.bytes, p.length), "query: a label that only ends like it");
    header(&p, 0, 0, 1, 0, 0, 0); question(&p, "_spotify-connect._tcp.local");
    CHECK(!SGMDNSIsConnectQuery(p.bytes, p.length), "query: one label holding the dots");
    p = query(); p.bytes[2] = 0x80;
    CHECK(!SGMDNSIsConnectQuery(p.bytes, p.length), "query: QR set");
    p = query(); p.bytes[2] = 0x08;
    CHECK(!SGMDNSIsConnectQuery(p.bytes, p.length), "query: opcode 1");
    p = query(); p.bytes[5] = 0;
    CHECK(!SGMDNSIsConnectQuery(p.bytes, p.length), "query: no question");
    p = query(); p.bytes[5] = 41;
    CHECK(!SGMDNSIsConnectQuery(p.bytes, p.length), "query: 41 questions");
    p = query(); p.bytes[5] = 2;
    CHECK(!SGMDNSIsConnectQuery(p.bytes, p.length), "query: a question missing");
    p = query();
    CHECK(!SGMDNSIsConnectQuery(p.bytes, p.length - 1), "query: cut short");
    CHECK(!SGMDNSIsConnectQuery(p.bytes, 11), "query: shorter than a header");
    CHECK(!SGMDNSIsConnectQuery(p.bytes, SGMDNSMaxLength + 1), "query: longer than 9000 bytes");
    header(&p, 0, 0, 1, 0, 0, 0); pointer(&p, 12); put16(&p, 12); put16(&p, 1);
    CHECK(!SGMDNSIsConnectQuery(p.bytes, p.length), "query: a name pointing at itself");
    header(&p, 0, 0, 1, 0, 0, 0); pointer(&p, 14); pointer(&p, 12); put16(&p, 12); put16(&p, 1);
    CHECK(!SGMDNSIsConnectQuery(p.bytes, p.length), "query: two pointers in a loop");
    header(&p, 0, 0, 1, 0, 0, 0); pointer(&p, 4000); put16(&p, 12); put16(&p, 1);
    CHECK(!SGMDNSIsConnectQuery(p.bytes, p.length), "query: a pointer past the end");
    header(&p, 0, 0, 1, 0, 0, 0); put8(&p, 63); p.length += 63;
    CHECK(!SGMDNSIsConnectQuery(p.bytes, p.length), "query: a label running off the end");
    header(&p, 0, 0, 1, 0, 0, 0); put8(&p, 0x40); put8(&p, 0); put16(&p, 12); put16(&p, 1);
    CHECK(!SGMDNSIsConnectQuery(p.bytes, p.length), "query: an extended label type");
    header(&p, 0, 0, 1, 0, 0, 0);
    for (int i = 0; i < 5; i++) { put8(&p, 63); memset(p.bytes + p.length, 'a', 63); p.length += 63; }
    put8(&p, 0); put16(&p, 12); put16(&p, 1);
    CHECK(!SGMDNSIsConnectQuery(p.bytes, p.length), "query: a name over 255 bytes");
}

static void checkReplies(void) {
    Packet p = reply(0x1234);
    CHECK(SGMDNSIsConnectReply(p.bytes, p.length, 0x1234), "reply: a PTR to an instance");
    CHECK(!SGMDNSIsConnectReply(p.bytes, p.length, 0x1235), "reply: another transaction ID");
    CHECK(!SGMDNSIsConnectReply(p.bytes, p.length - 1, 0x1234), "reply: cut short");
    p = reply(0x1234); p.bytes[2] |= 0x02;
    CHECK(!SGMDNSIsConnectReply(p.bytes, p.length, 0x1234), "reply: truncated (TC)");
    p = reply(0x1234); p.bytes[3] |= 0x03;
    CHECK(!SGMDNSIsConnectReply(p.bytes, p.length, 0x1234), "reply: RCODE 3");
    p = reply(0x1234); p.bytes[2] &= 0x7F;
    CHECK(!SGMDNSIsConnectReply(p.bytes, p.length, 0x1234), "reply: QR clear");
    p = reply(0x1234); p.bytes[2] |= 0x10;
    CHECK(!SGMDNSIsConnectReply(p.bytes, p.length, 0x1234), "reply: opcode 2");
    p = reply(0x1234); p.bytes[7] = 0;
    CHECK(!SGMDNSIsConnectReply(p.bytes, p.length, 0x1234), "reply: no records");
    p = reply(0x1234); p.bytes[7] = 2;
    CHECK(!SGMDNSIsConnectReply(p.bytes, p.length, 0x1234), "reply: a record missing");
    header(&p, 1, 0x8400, 0, 401, 0, 0);
    CHECK(!SGMDNSIsConnectReply(p.bytes, p.length, 1), "reply: 401 records");

    // An SRV owned by the instance, with mDNS's cache flush bit on its class.
    header(&p, 1, 0x8400, 0, 1, 0, 0); name(&p, "Living.Room|_spotify-connect|_tcp|local"); record(&p, 33, 0x8001, 0);
    CHECK(SGMDNSIsConnectReply(p.bytes, p.length, 1), "reply: an instance's record, cache flush set, a dot in its name");
    header(&p, 1, 0x8400, 0, 1, 0, 0); name(&p, "Living|_spotify-connect|_tcp|local"); record(&p, 33, 3, 0);
    CHECK(!SGMDNSIsConnectReply(p.bytes, p.length, 1), "reply: class CH");
    header(&p, 1, 0x8400, 0, 0, 0, 1); name(&p, "tv|_googlecast|_tcp|local"); record(&p, 1, 1, 4); put16(&p, 0); put16(&p, 0);
    CHECK(!SGMDNSIsConnectReply(p.bytes, p.length, 1), "reply: Cast only");
    header(&p, 1, 0x8400, 0, 1, 0, 1); name(&p, "tv|_googlecast|_tcp|local"); record(&p, 1, 1, 4); put16(&p, 0); put16(&p, 0);
    name(&p, "Desk|_spotify-connect|_tcp|local"); record(&p, 16, 1, 0);
    CHECK(SGMDNSIsConnectReply(p.bytes, p.length, 1), "reply: Connect in the additional section");
    header(&p, 1, 0x8400, 0, 1, 0, 0); name(&p, "Desk|_spotify-connect|_tcp|local"); record(&p, 16, 1, 50);
    CHECK(!SGMDNSIsConnectReply(p.bytes, p.length, 1), "reply: data running off the end");
    header(&p, 1, 0x8400, 0, 1, 0, 0); pointer(&p, 12); record(&p, 16, 1, 0);
    CHECK(!SGMDNSIsConnectReply(p.bytes, p.length, 1), "reply: an owner pointing at itself");
    header(&p, 1, 0x8400, 0, 1, 0, 0); name(&p, "_services|_dns-sd|_udp|local"); record(&p, 12, 1, 2); pointer(&p, 3000);
    CHECK(!SGMDNSIsConnectReply(p.bytes, p.length, 1), "reply: a PTR target past the end");
    header(&p, 1, 0x8400, 0, 1, 0, 0); name(&p, "_services|_dns-sd|_udp|local"); record(&p, 12, 1, 1); put8(&p, 5); put8(&p, 'a');
    CHECK(!SGMDNSIsConnectReply(p.bytes, p.length, 1), "reply: a PTR target longer than its data");
    header(&p, 1, 0x8400, 0, 2, 0, 0); name(&p, "Desk|_spotify-connect|_tcp|local"); record(&p, 16, 1, 0);
    name(&p, "x|local"); record(&p, 12, 1, 2); pointer(&p, 5000);
    CHECK(!SGMDNSIsConnectReply(p.bytes, p.length, 1), "reply: a Connect record, then a name that does not decode");
}

// Random bytes changed in a good query and a good answer, read by both checks: under the sanitizers
// (README) any read past a packet's end stops the run.
static void checkMutations(void) {
    srandom(159);
    int accepted = 0;
    for (int round = 0; round < 200000; round++) {
        Packet p = round & 1 ? reply(7) : query();
        for (int k = 0, changes = 1 + (int)(random() % 4); k < changes; k++) p.bytes[random() % p.length] = (uint8_t)random();
        size_t length = p.length - (size_t)(random() % 3);
        uint8_t *copy = malloc(length); // exactly the packet's size, so the sanitizer sees a read past it
        memcpy(copy, p.bytes, length);
        accepted += SGMDNSIsConnectQuery(copy, length) + SGMDNSIsConnectReply(copy, length, 7);
        free(copy);
    }
    printf("ok   200000 changed packets read, %d still accepted\n", accepted);
}

#pragma mark - the hook's gate

static int sg_fakeErrno;
static int sg_fakeCalls;
static ssize_t failingSendto(int s, const void *b, size_t l, int f, const struct sockaddr *to, socklen_t tl) {
    sg_fakeCalls++;
    if (!sg_fakeErrno) return (ssize_t)l;
    errno = sg_fakeErrno;
    return -1;
}
static ssize_t failingSendmsg(int s, const struct msghdr *m, int f) {
    sg_fakeCalls++;
    errno = sg_fakeErrno;
    return -1;
}

static struct sockaddr_in loopbackV4(in_port_t port) {
    return (struct sockaddr_in){.sin_len = sizeof(struct sockaddr_in), .sin_family = AF_INET, .sin_port = port, .sin_addr.s_addr = htonl(INADDR_LOOPBACK)};
}
static struct sockaddr_in6 loopbackV6(in_port_t port) {
    return (struct sockaddr_in6){.sin6_len = sizeof(struct sockaddr_in6), .sin6_family = AF_INET6, .sin6_port = port, .sin6_addr = in6addr_loopback};
}

// A UDP socket bound to an ephemeral loopback port, reads timing out after `timeout` s.
static int boundSocket(int family, double timeout, in_port_t *port) {
    int s = socket(family, SOCK_DGRAM, IPPROTO_UDP);
    struct sockaddr_storage address = {0};
    if (family == AF_INET6) *(struct sockaddr_in6 *)&address = loopbackV6(0);
    else *(struct sockaddr_in *)&address = loopbackV4(0);
    if (bind(s, (struct sockaddr *)&address, address.ss_len) != 0) { perror("bind"); exit(2); }
    socklen_t length = sizeof address;
    getsockname(s, (struct sockaddr *)&address, &length);
    if (port) *port = family == AF_INET6 ? ((struct sockaddr_in6 *)&address)->sin6_port : ((struct sockaddr_in *)&address)->sin_port;
    struct timeval wait = {(int)timeout, (int)((timeout - (int)timeout) * 1e6)};
    setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &wait, sizeof wait);
    return s;
}

static void checkGate(void) {
    SGConnectRealSendto = failingSendto;
    SGConnectRealSendmsg = failingSendmsg;
    Packet q = query();
    struct sockaddr_in group = {.sin_len = sizeof group, .sin_family = AF_INET, .sin_port = htons(5353), .sin_addr.s_addr = inet_addr("224.0.0.251")};
    struct sockaddr_in6 group6 = {.sin6_len = sizeof group6, .sin6_family = AF_INET6, .sin6_port = htons(5353)};
    inet_pton(AF_INET6, "ff02::fb", &group6.sin6_addr);
    int bound = boundSocket(AF_INET, 1, NULL), bound6 = boundSocket(AF_INET6, 1, NULL);

    sg_fakeErrno = EHOSTUNREACH;
    errno = 0;
    ssize_t sent = SGConnectSendto(bound, q.bytes, q.length, 0, (struct sockaddr *)&group, sizeof group);
    CHECK(sent == (ssize_t)q.length && errno == EHOSTUNREACH, "sendto: refused Connect query reported sent, errno kept");
    sent = SGConnectSendto(bound6, q.bytes, q.length, 0, (struct sockaddr *)&group6, sizeof group6);
    CHECK(sent == (ssize_t)q.length, "sendto: the same over IPv6 to ff02::fb");
    sg_fakeErrno = EINVAL;
    sent = SGConnectSendto(bound, q.bytes, q.length, 0, (struct sockaddr *)&group, sizeof group);
    CHECK(sent == -1 && errno == EINVAL, "sendto: another error stays");
    sg_fakeErrno = EPERM;
    Packet notConnect;
    header(&notConnect, 0, 0, 1, 0, 0, 0); question(&notConnect, "_googlecast|_tcp|local");
    sent = SGConnectSendto(bound, notConnect.bytes, notConnect.length, 0, (struct sockaddr *)&group, sizeof group);
    CHECK(sent == -1 && errno == EPERM, "sendto: a Cast query stays refused");
    struct sockaddr_in elsewhere = group;
    elsewhere.sin_addr.s_addr = inet_addr("224.0.0.252");
    sent = SGConnectSendto(bound, q.bytes, q.length, 0, (struct sockaddr *)&elsewhere, sizeof elsewhere);
    CHECK(sent == -1, "sendto: another group stays refused");
    elsewhere = group;
    elsewhere.sin_port = htons(5354);
    sent = SGConnectSendto(bound, q.bytes, q.length, 0, (struct sockaddr *)&elsewhere, sizeof elsewhere);
    CHECK(sent == -1, "sendto: another port stays refused");
    sent = SGConnectSendto(bound, q.bytes, q.length, 0, (struct sockaddr *)&group, 4);
    CHECK(sent == -1, "sendto: an address too short to read stays refused");

    int unbound = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    sent = SGConnectSendto(unbound, q.bytes, q.length, 0, (struct sockaddr *)&group, sizeof group);
    CHECK(sent == -1 && errno == EPERM, "sendto: a socket with no port stays refused");
    int connected = boundSocket(AF_INET, 1, NULL);
    struct sockaddr_in peer = loopbackV4(htons(9));
    connect(connected, (struct sockaddr *)&peer, sizeof peer);
    sent = SGConnectSendto(connected, q.bytes, q.length, 0, (struct sockaddr *)&group, sizeof group);
    CHECK(sent == -1 && errno == EPERM, "sendto: a connected socket stays refused");
    int stream = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    sent = SGConnectSendto(stream, q.bytes, q.length, 0, (struct sockaddr *)&group, sizeof group);
    CHECK(sent == -1 && errno == EPERM, "sendto: a TCP socket stays refused");

    sg_fakeErrno = 0;
    sent = SGConnectSendto(bound, q.bytes, 3, 0, (struct sockaddr *)&group, sizeof group);
    CHECK(sent == 3, "sendto: a send that worked is left alone");

    sg_fakeErrno = ENETUNREACH;
    struct iovec parts[2] = {{q.bytes, 5}, {q.bytes + 5, q.length - 5}};
    struct msghdr message = {.msg_name = &group, .msg_namelen = sizeof group, .msg_iov = parts, .msg_iovlen = 2};
    sent = SGConnectSendmsg(bound, &message, 0);
    CHECK(sent == (ssize_t)q.length && errno == ENETUNREACH, "sendmsg: a query in two parts reported sent, errno kept");
    message.msg_name = NULL;
    sent = SGConnectSendmsg(bound, &message, 0);
    CHECK(sent == -1, "sendmsg: no destination stays refused");
    close(bound); close(bound6); close(unbound); close(connected); close(stream);
    usleep(1300000); // the rounds started above end
}

#pragma mark - the relay over loopback

static void checkRelay(int family) {
    const char *label = family == AF_INET6 ? "relay (IPv6 socket, IPv4 receiver)" : "relay (IPv4)";
    char what[160];
    in_port_t receiverPort, strangerPort;
    int spotify = boundSocket(family, 1.5, NULL);
    int receiver = boundSocket(AF_INET, 1, &receiverPort), stranger = boundSocket(AF_INET, 1, &strangerPort);
    struct sockaddr_in receiverAddress = loopbackV4(receiverPort);
    SGConnectSetReceiver(@"Kitchen", @[[NSData dataWithBytes:&receiverAddress length:sizeof receiverAddress]]);

    sg_fakeErrno = EHOSTUNREACH;
    Packet q = query();
    q.bytes[0] = 0x12; q.bytes[1] = 0x34;
    struct sockaddr_in group = {.sin_len = sizeof group, .sin_family = AF_INET, .sin_port = htons(5353), .sin_addr.s_addr = inet_addr("224.0.0.251")};
    struct sockaddr_in6 group6 = {.sin6_len = sizeof group6, .sin6_family = AF_INET6, .sin6_port = htons(5353)};
    inet_pton(AF_INET6, "ff02::fb", &group6.sin6_addr);
    const struct sockaddr *to = family == AF_INET6 ? (struct sockaddr *)&group6 : (struct sockaddr *)&group;
    SGConnectSendto(spotify, q.bytes, q.length, 0, to, to->sa_len);
    SGConnectSendto(spotify, q.bytes, q.length, 0, to, to->sa_len); // the same again while the round runs

    uint8_t buffer[SGMDNSMaxLength];
    struct sockaddr_in relay;
    socklen_t relayLength = sizeof relay;
    ssize_t got = recvfrom(receiver, buffer, sizeof buffer, 0, (struct sockaddr *)&relay, &relayLength);
    snprintf(what, sizeof what, "%s: the receiver gets the query", label);
    CHECK(got == (ssize_t)q.length && memcmp(buffer, q.bytes, q.length) == 0, what);

    // Answered at once: the round, having sent all it had to, ends 0.7 s in.
    Packet wrong = reply(0x4321), good = reply(0x1234), fromStranger = reply(0x1234);
    fromStranger.bytes[fromStranger.length - 3] = 'X'; // told apart from the good one
    sendto(receiver, wrong.bytes, wrong.length, 0, (struct sockaddr *)&relay, relayLength);
    sendto(stranger, fromStranger.bytes, fromStranger.length, 0, (struct sockaddr *)&relay, relayLength);
    sendto(receiver, good.bytes, good.length, 0, (struct sockaddr *)&relay, relayLength);

    got = recvfrom(receiver, buffer, sizeof buffer, 0, NULL, NULL);
    snprintf(what, sizeof what, "%s: and only once", label);
    CHECK(got < 0, what);

    struct sockaddr_storage from;
    socklen_t fromLength = sizeof from;
    got = SGConnectRecvfrom(spotify, buffer, sizeof buffer, MSG_PEEK, (struct sockaddr *)&from, &fromLength);
    snprintf(what, sizeof what, "%s: Spotify's socket gets the answer", label);
    CHECK(got == (ssize_t)good.length && memcmp(buffer, good.bytes, good.length) == 0, what);
    BOOL fromReceiver;
    if (family == AF_INET6) {
        struct sockaddr_in6 *v6 = (struct sockaddr_in6 *)&from;
        fromReceiver = fromLength == sizeof *v6 && v6->sin6_family == AF_INET6 && v6->sin6_port == receiverPort
            && IN6_IS_ADDR_V4MAPPED(&v6->sin6_addr) && v6->sin6_addr.s6_addr[12] == 127 && v6->sin6_addr.s6_addr[15] == 1;
    } else {
        struct sockaddr_in *v4 = (struct sockaddr_in *)&from;
        fromReceiver = fromLength == sizeof *v4 && v4->sin_port == receiverPort && v4->sin_addr.s_addr == htonl(INADDR_LOOPBACK);
    }
    snprintf(what, sizeof what, "%s: from the receiver's address (peeked)", label);
    CHECK(fromReceiver, what);

    struct sockaddr_storage again = {0};
    socklen_t againLength = sizeof again;
    got = SGConnectRecvfrom(spotify, buffer, sizeof buffer, 0, (struct sockaddr *)&again, &againLength);
    snprintf(what, sizeof what, "%s: read again, kept after the peek", label);
    CHECK(got == (ssize_t)good.length && againLength == fromLength && memcmp(&again, &from, fromLength) == 0, what);

    got = SGConnectRecvfrom(spotify, buffer, sizeof buffer, 0, (struct sockaddr *)&from, &fromLength);
    snprintf(what, sizeof what, "%s: nothing else reaches Spotify (wrong ID, a stranger)", label);
    CHECK(got < 0, what);

    // A datagram from loopback that was never handed over keeps its source.
    in_port_t otherPort;
    int other = boundSocket(family, 1, &otherPort);
    struct sockaddr_storage spotifyAddress;
    socklen_t spotifyLength = sizeof spotifyAddress;
    getsockname(spotify, (struct sockaddr *)&spotifyAddress, &spotifyLength);
    sendto(other, good.bytes, good.length - 1, 0, (struct sockaddr *)&spotifyAddress, spotifyLength);
    fromLength = sizeof from;
    got = SGConnectRecvfrom(spotify, buffer, sizeof buffer, 0, (struct sockaddr *)&from, &fromLength);
    in_port_t seenPort = family == AF_INET6 ? ((struct sockaddr_in6 *)&from)->sin6_port : ((struct sockaddr_in *)&from)->sin_port;
    snprintf(what, sizeof what, "%s: other loopback traffic keeps its source", label);
    CHECK(got == (ssize_t)good.length - 1 && seenPort == otherPort, what);

    SGConnectSetReceiver(@"Kitchen", nil);
    close(spotify); close(receiver); close(stranger); close(other);
    usleep(1300000);
}

int main(void) {
    @autoreleasepool {
        checkQueries();
        checkReplies();
        checkMutations();
        checkGate();
        checkRelay(AF_INET);
        checkRelay(AF_INET6);
    }
    printf(failures ? "%d FAILED\n" : "all passed\n", failures);
    return failures ? 1 : 0;
}
