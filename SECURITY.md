# Security and privacy reporting

Please use a private [GitHub Security Advisory](https://github.com/Sapphire-Rapids/FindUAS/security/advisories/new)
for vulnerabilities or reports that cannot be explained without sensitive receiver or flight data.
Do not open a public issue containing real UAS IDs, receiver serial numbers, exact locations, phone
numbers, full telemetry logs, or credentials.

The application has no account or telemetry-upload service. It stores a local, unencrypted JSONL
history under the user's Application Support directory. Anyone with access to that macOS account
may be able to read recorded aircraft and operator locations.

This project is not a safety-of-flight system. Do not rely on it for collision avoidance, law
enforcement decisions, emergency response, or identity attribution.
