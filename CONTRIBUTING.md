# Contributing

Thanks for helping improve FindUASMac. Start with [AGENTS.md](AGENTS.md) and
[the architecture notes](docs/ARCHITECTURE.md); both are written for human and automated
contributors.

## Development workflow

1. Create a focused branch and keep unrelated formatting changes out of the patch.
2. Add a regression check for protocol, decoder, persistence, or state bugs.
3. Run `./scripts/check.sh` and `./scripts/build-app.sh`.
4. Update the README, protocol notes, and changelog when behavior or compatibility changes.
5. Open a pull request explaining the observed behavior, the fix, and how it was verified.

Protocol contributions should use minimal synthetic or redacted fixtures. Do not attach a complete
flight log merely to demonstrate one field alias.

## Hardware reports

Useful reports include receiver model, firmware version, macOS version, transport mode, packet
sizes, counter behavior, redacted field names/types, and diagnostic counters. Remove aircraft and
receiver identifiers, precise coordinates, phone numbers, and timestamps that identify a flight.

## Scope and safety

Do not write FF03 without documented evidence and explicit review. Do not add private-database
queries, identity correlation, or telemetry uploads. This project receives broadcasts and controls
only a receiver the user is authorized to operate.

By submitting a contribution, you agree that it is licensed under the repository's MIT License.
