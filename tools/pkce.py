#!/usr/bin/env python3
"""
PKCE (RFC 7636) helper for testing/debugging.
Generates a `code_verifier` and corresponding S256 `code_challenge`.

Usage:
  python3 tools/pkce.py                # prints verifier + challenge
  python3 tools/pkce.py --json         # prints JSON
  python3 tools/pkce.py --verifier XYZ # use a specific verifier
  python3 tools/pkce.py --length 64    # generate with given length (43-128)

Notes:
- `code_verifier` must be 43-128 chars from ALPHA / DIGIT / "-" / "." / "_" / "~".
- We generate a URL-safe base64 string and strip padding to satisfy the spec.
"""
import argparse
import base64
import hashlib
import os
import secrets
import sys
import json

ALLOWED_CHARS = set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")


def make_verifier(length: int = 64) -> str:
    if length < 43 or length > 128:
        raise ValueError("length must be between 43 and 128")
    # Generate random bytes and base64url-encode, then strip padding.
    raw = secrets.token_bytes(length)
    verifier = base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")
    # Ensure only allowed characters (trim if needed to meet upper bound)
    verifier = "".join(ch for ch in verifier if ch in ALLOWED_CHARS)
    if len(verifier) < 43:
        # Fallback: pad with allowed random chars until minimum length
        alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        verifier += "".join(secrets.choice(alphabet) for _ in range(43 - len(verifier)))
    return verifier[:min(len(verifier), 128)]


def make_challenge_s256(verifier: str) -> str:
    digest = hashlib.sha256(verifier.encode("ascii")).digest()
    return base64.urlsafe_b64encode(digest).decode("ascii").rstrip("=")


def main(argv=None):
    parser = argparse.ArgumentParser(description="PKCE S256 generator")
    parser.add_argument("--verifier", help="Use a specific code_verifier (else generate)")
    parser.add_argument("--length", type=int, default=64, help="Length for generated verifier (43-128)")
    parser.add_argument("--json", action="store_true", help="Output as JSON")
    args = parser.parse_args(argv)

    verifier = args.verifier or make_verifier(args.length)
    challenge = make_challenge_s256(verifier)

    if args.json:
        print(json.dumps({"code_verifier": verifier, "code_challenge": challenge, "method": "S256"}, indent=2))
    else:
        print("code_verifier:", verifier)
        print("code_challenge:", challenge)
        print("code_challenge_method: S256")


if __name__ == "__main__":
    sys.exit(main())
