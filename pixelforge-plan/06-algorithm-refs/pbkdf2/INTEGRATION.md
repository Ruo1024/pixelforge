# PBKDF2 integration note

- Source: IETF RFC 8018, PKCS #5 v2.1, §5.2 PBKDF2 and Appendix B.1.2 HMAC-SHA-2: https://www.rfc-editor.org/rfc/rfc8018
- Status/license: IETF informational RFC. Code components extracted from the RFC are available under the Simplified BSD License terms described by the IETF Trust Legal Provisions; this repository does not copy RFC code.
- PixelForge use: `pixel/services/credential_store.gd` implements the RFC PBKDF2 block/XOR construction with HMAC-SHA-256, verified against a published-compatible reference vector. It derives independent AES-256 and HMAC keys from the device identifier and a random per-provider salt.
- Deliberate profile: 20,000 iterations, 16-byte salt, 64-byte derived output. This protects against accidental plaintext disclosure, not malicious software executing as the same user; see the source header threat-model note.
- Supporting engine primitives: Godot 4.6 `AESContext` (AES-CBC), `Crypto.generate_random_bytes`, `Crypto.hmac_digest`, and constant-time MAC comparison.
