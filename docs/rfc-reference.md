# RFC Reference

This document provides an overview of the RFCs implemented by estun.

## Implemented RFCs

### RFC 5389 - STUN (Primary)

**Session Traversal Utilities for NAT**

The core STUN protocol specification. estun fully implements this RFC.

**Key Features:**

- Message format and encoding
- Transaction handling with retransmission
- MESSAGE-INTEGRITY (HMAC-SHA1)
- FINGERPRINT (CRC-32)
- XOR-MAPPED-ADDRESS
- Short-term and long-term authentication

**Reference:** [RFC 5389](https://datatracker.ietf.org/doc/html/rfc5389)

### RFC 5769 - Test Vectors

**Test Vectors for STUN**

Provides test vectors for verifying STUN implementations.

**Implementation:** All test vectors pass in `estun_codec_tests.erl`

**Reference:** [RFC 5769](https://datatracker.ietf.org/doc/html/rfc5769)

### RFC 5780 - NAT Behavior Discovery

**NAT Behavior Discovery Using STUN**

Extensions for discovering NAT behavior (mapping and filtering).

**Key Features:**

- OTHER-ADDRESS attribute
- CHANGE-REQUEST attribute
- RESPONSE-PORT attribute
- NAT mapping behavior tests
- NAT filtering behavior tests

**Implementation:** `estun_nat_discovery.erl`

**Reference:** [RFC 5780](https://datatracker.ietf.org/doc/html/rfc5780)

### RFC 3489 - Classic STUN (Compatibility)

**STUN - Simple Traversal of UDP Through NATs**

The original STUN specification (obsoleted by RFC 5389).

**Implementation:** Basic compatibility for decoding legacy messages.

**Reference:** [RFC 3489](https://datatracker.ietf.org/doc/html/rfc3489)

## Planned RFCs

### RFC 7443 - ALPN for STUN (P2)

**Application-Layer Protocol Negotiation (ALPN) Labels for STUN**

TLS extension for STUN over TLS.

**Status:** Planned for future release

**Reference:** [RFC 7443](https://datatracker.ietf.org/doc/html/rfc7443)

### RFC 7635 - OAuth for STUN (P2)

**Session Traversal Utilities for NAT (STUN) Extension for Third-Party Authorization**

OAuth-based authentication for STUN/TURN.

**Status:** Planned for future release

**Reference:** [RFC 7635](https://datatracker.ietf.org/doc/html/rfc7635)

## Message Format (RFC 5389)

### Header

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|0 0|     STUN Message Type     |         Message Length        |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                         Magic Cookie                          |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                                                               |
|                     Transaction ID (96 bits)                  |
|                                                               |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

### Message Type

```
 0                 1
 2  3  4 5 6 7 8 9 0 1 2 3 4 5
+--+--+-+-+-+-+-+-+-+-+-+-+-+-+
|M |M |M|M|M|C|M|M|M|C|M|M|M|M|
|11|10|9|8|7|1|6|5|4|0|3|2|1|0|
+--+--+-+-+-+-+-+-+-+-+-+-+-+-+

M = Method bits
C = Class bits
```

### Classes

| Class | C1 C0 | Description |
|-------|-------|-------------|
| Request | 0b00 | Client request |
| Indication | 0b01 | No response |
| Success | 0b10 | Success response |
| Error | 0b11 | Error response |

### Methods

| Method | Value | Description |
|--------|-------|-------------|
| Binding | 0x001 | Binding request/response |

## Attributes (RFC 5389)

### Attribute Header

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|         Type                  |            Length             |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                         Value (variable)                ....
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

### Attribute Types

#### Comprehension Required (0x0000-0x7FFF)

| Type | Name | RFC |
|------|------|-----|
| 0x0001 | MAPPED-ADDRESS | 5389 |
| 0x0003 | CHANGE-REQUEST | 5780 |
| 0x0006 | USERNAME | 5389 |
| 0x0008 | MESSAGE-INTEGRITY | 5389 |
| 0x0009 | ERROR-CODE | 5389 |
| 0x000A | UNKNOWN-ATTRIBUTES | 5389 |
| 0x0014 | REALM | 5389 |
| 0x0015 | NONCE | 5389 |
| 0x0020 | XOR-MAPPED-ADDRESS | 5389 |

#### Comprehension Optional (0x8000-0xFFFF)

| Type | Name | RFC |
|------|------|-----|
| 0x8022 | SOFTWARE | 5389 |
| 0x8023 | ALTERNATE-SERVER | 5389 |
| 0x8028 | FINGERPRINT | 5389 |
| 0x802b | RESPONSE-ORIGIN | 5780 |
| 0x802c | OTHER-ADDRESS | 5780 |

## XOR-MAPPED-ADDRESS (RFC 5389)

### XOR Encoding

```
X-Port = Port XOR (Magic Cookie >> 16)
X-Address = Address XOR Magic Cookie (IPv4)
X-Address = Address XOR (Magic Cookie || Transaction ID) (IPv6)
```

### Magic Cookie

```erlang
-define(STUN_MAGIC, 16#2112A442).
```

## Error Codes (RFC 5389)

| Code | Name | Description |
|------|------|-------------|
| 300 | Try Alternate | Use alternate server |
| 400 | Bad Request | Malformed request |
| 401 | Unauthorized | Auth required |
| 420 | Unknown Attribute | Unknown required attribute |
| 438 | Stale Nonce | Nonce expired |
| 500 | Server Error | Internal server error |

## Retransmission (RFC 5389)

### Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| Initial RTO | 500ms | First timeout |
| Max RTO | 8000ms | Maximum timeout |
| Rc | 7 | Max retransmissions |
| Rm | 16 | Reliability multiplier |

### RTO Calculation

```
RTO(n) = min(500 * 2^n, 8000) milliseconds
```

### Total Duration

```
Total = 500 + 1000 + 2000 + 4000 + 8000 + 8000 + 8000 = 31500ms
+ final RTO wait = ~39500ms
```

## NAT Behavior (RFC 5780)

### Mapping Behaviors

| Behavior | Description |
|----------|-------------|
| Endpoint Independent | Same mapping for all destinations |
| Address Dependent | Different mapping per dest IP |
| Address+Port Dependent | Different mapping per dest IP:port |

### Filtering Behaviors

| Behavior | Description |
|----------|-------------|
| Endpoint Independent | Accept from any source |
| Address Dependent | Only from contacted IPs |
| Address+Port Dependent | Only from contacted IP:port |

## Related RFCs

- **RFC 5245** - ICE (Interactive Connectivity Establishment)
- **RFC 5766** - TURN (Traversal Using Relays around NAT)
- **RFC 6544** - TCP Candidates with ICE
- **RFC 8445** - ICE (Updated)
- **RFC 8656** - TURN (Updated)
