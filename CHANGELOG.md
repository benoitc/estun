# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1] - 2026-02-22

### Fixed

- Documentation URLs now point to GitHub Pages

## [0.1.0] - 2026-02-22

### Added

- STUN binding requests and responses (RFC 5389)
- NAT behavior discovery (RFC 5780)
- Test vectors verification (RFC 5769)
- Classic STUN compatibility (RFC 3489)
- UDP hole punching with configurable keepalive
- Socket transfer for P2P traffic handoff
- Short-term and long-term authentication
- IPv4 and IPv6 support
- Event handlers for binding lifecycle (pid or function)
- Server pool management with named servers
- Transaction management with RFC 5389 retransmission logic
- MESSAGE-INTEGRITY and FINGERPRINT attribute support

### Technical

- Pure Erlang implementation using OTP 28+ `socket` module
- gen_statem-based client state machine
- Supervisor tree with dynamic client processes

[0.1.1]: https://github.com/benoitc/estun/releases/tag/v0.1.1
[0.1.0]: https://github.com/benoitc/estun/releases/tag/v0.1.0
