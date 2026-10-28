# Connect discovery harness

`SGMDNS.m` and `SGConnectRelay.m` (Shared/Connect) as the tweak compiles them, on the Mac.

- The packet checks over queries and answers made by hand: the service type, a subtype, upper case, a
  compressed name, and the ones to turn away (Cast only, a label that only ends like Connect's, QR or
  opcode wrong, too many questions, cut short, compression loops, pointers and labels past the end, a name
  over 255 bytes; in answers another transaction ID, TC, an RCODE, class CH, data or a PTR target running
  past its end). Then 200,000 packets with random bytes changed, read by both checks.
- The gate of the sendto and sendmsg replacements, with the system's send stood in for by one that fails
  with the error given: a refused Connect query to 224.0.0.251:5353 or [ff02::fb]:5353 is reported sent with
  errno as it was, and anything else (another error, a Cast query, another group or port, a socket with no
  port, a connected one, TCP) keeps the failure.
- A whole round over loopback, for an IPv4 socket and for an IPv6 one: a stand-in receiver on 127.0.0.1
  gets the query once (the same query sent again while the round runs starts no second round), answers it
  with a wrong ID and the right one while a stranger answers too, and the stand-in for Spotify's socket reads
  only the right one, from the receiver's address (`::ffff:127.0.0.1` for the IPv6 socket), through a
  `MSG_PEEK` and again after it. Other loopback traffic keeps its source.

The receivers here listen on ephemeral ports rather than 5353, which the Mac's mDNSResponder holds; the
round answers to whatever port it sent to, which on the phone is always 5353.

    ./build.sh && build/connect        # binds loopback ports, so not inside a sandbox without local binding

With the sanitizers, which turn any read past a packet's end into a stop:

    xcrun clang -fobjc-arc -O1 -g -fsanitize=address,undefined -I ../../tweak/Sources -framework Foundation \
        main.m ../../tweak/Sources/Shared/Connect/SGMDNS.m ../../tweak/Sources/Shared/Connect/SGConnectRelay.m \
        -o build/connect-asan && build/connect-asan

Not covered: the Bonjour browse in Connect.x, the rebinding of Spotify's imports, and whether the phone
hands a loopback datagram for port 5353 to Spotify's socket rather than mDNSResponder's. Those need a
phone on a network with a Connect receiver.
