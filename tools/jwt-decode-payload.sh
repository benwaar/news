#!/usr/bin/env bash
set -euo pipefail

# jwt-decode-payload.sh — Print the JSON payload of a JWT
# Usage examples:
#   echo "$JWT" | tools/jwt-decode-payload.sh
#   tools/jwt-decode-payload.sh "$JWT"
#   TOKEN="$JWT" tools/jwt-decode-payload.sh
#   tools/jwt-decode-payload.sh --clipboard   # macOS pbpaste
#   tools/jwt-decode-payload.sh --file /path/to/token.txt

show_help() {
  cat <<EOF
Usage: jwt-decode-payload.sh [--clipboard|-c] [--file|-f FILE] [--field|-k KEY] [--compact|-m] [JWT]

Reads a JWT from one of, in priority order:
  1) --clipboard (macOS pbpaste)
  2) --file FILE
  3) positional JWT argument
  4) TOKEN or ACCESS_TOKEN environment variable
  5) stdin (pipe)

Examples:
  echo "$JWT" | tools/jwt-decode-payload.sh
  tools/jwt-decode-payload.sh --clipboard
  tools/jwt-decode-payload.sh --file token.txt
  TOKEN="$JWT" tools/jwt-decode-payload.sh

Options:
  --field, -k KEY   Print only a single top-level claim from the payload (e.g., idp)
  --compact, -m     Print compact JSON on a single line (useful for VAR=$(...))
EOF
}

CLIPBOARD=false
FILE_ARG=""
TOKEN_ARG=""
FIELD_ARG=""
COMPACT=false

ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --clipboard|-c)
      CLIPBOARD=true; shift ;;
    --file|-f)
      FILE_ARG="${2:-}"; shift 2 ;;
    --token|-t)
      TOKEN_ARG="${2:-}"; shift 2 ;;
    --field|-k)
      FIELD_ARG="${2:-}"; shift 2 ;;
    --compact|-m)
      COMPACT=true; shift ;;
    --help|-h)
      show_help; exit 0 ;;
    *)
      ARGS+=("$1"); shift ;;
  esac
done

POS_ARG="${ARGS[0]:-}"

read_token() {
  if [[ "$CLIPBOARD" == true ]]; then
    if ! command -v pbpaste >/dev/null 2>&1; then
      echo "--clipboard requested but 'pbpaste' not found (macOS only)" >&2
      exit 2
    fi
    CLIP=$(pbpaste | LC_CTYPE=C tr -d '[:space:]')
    if [[ -z "$CLIP" || "${CLIP//.}" == "$CLIP" ]]; then
      echo "Clipboard is empty or not a JWT. Paste token and press Ctrl-D:" >&2
      CLIP=$(cat | LC_CTYPE=C tr -d '[:space:]' || true)
    fi
    echo -n "$CLIP"
  elif [[ -n "$FILE_ARG" ]]; then
    [[ -f "$FILE_ARG" ]] || { echo "File not found: $FILE_ARG" >&2; exit 2; }
    LC_CTYPE=C tr -d '[:space:]' < "$FILE_ARG"
  elif [[ -n "$TOKEN_ARG" ]]; then
    echo -n "$TOKEN_ARG"
  elif [[ -n "$POS_ARG" ]]; then
    echo -n "$POS_ARG"
  elif [[ -n "${TOKEN:-}" ]]; then
    echo -n "$TOKEN"
  elif [[ -n "${ACCESS_TOKEN:-}" ]]; then
    echo -n "$ACCESS_TOKEN"
  else
    # Read from stdin
    if [ -t 0 ]; then
      show_help >&2
      exit 2
    fi
    LC_CTYPE=C tr -d '[:space:]'
  fi
}

JWT=$(read_token)
# If clipboard/file/stdin contained surrounding text, try extracting a JWT-like substring
if [[ "${JWT//.}" == "$JWT" || ${#JWT} -lt 20 ]]; then
  CAND=$(printf "%s" "$JWT" | grep -Eo '[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+' | head -n1 || true)
  if [[ -n "$CAND" ]]; then
    JWT="$CAND"
  fi
fi

JWT_INPUT="$JWT" JWT_FIELD="$FIELD_ARG" JWT_COMPACT="$COMPACT" python3 - <<'PY'
import os, sys, json, base64

def b64pad(s: str) -> str:
    return s + "=" * (-len(s) % 4)

t = os.environ.get('JWT_INPUT', '').strip()
# If input doesn't look like a JWT, try to extract first token-like substring
candidate = t
if t.count('.') < 2:
  for w in t.replace('\n', ' ').split(' '):
    if w.count('.') >= 2 and len(w) > 30:
      candidate = w.strip('\"\'')
      break

parts = candidate.split('.')
if len(parts) < 2:
  snippet = candidate[:96]
  print(f"Invalid JWT: missing payload. Got: '{snippet}...' (len={len(candidate)}, dots={candidate.count('.')})", file=sys.stderr)
  sys.exit(1)

payload_b64 = b64pad(parts[1])
try:
    decoded = base64.urlsafe_b64decode(payload_b64)
    try:
        obj = json.loads(decoded)
        field = os.environ.get('JWT_FIELD', '').strip()
        compact = os.environ.get('JWT_COMPACT', 'false').lower() == 'true'

        def dump(o):
            if compact:
                return json.dumps(o, separators=(',', ':'), ensure_ascii=False)
            return json.dumps(o, indent=2, ensure_ascii=False)

        if field:
            # Only print the requested top-level key
            val = obj.get(field, None)
            if isinstance(val, (dict, list)):
                print(dump(val))
            elif val is None:
                # Print empty string on missing key to ease VAR assignment
                print("")
            else:
                # Scalar: print as-is
                print(val)
        else:
            print(dump(obj))
    except json.JSONDecodeError:
        # Not JSON? Print raw
        print(decoded.decode('utf-8', errors='replace'))
except Exception as e:
    print(f"Decode error: {e}", file=sys.stderr)
    sys.exit(1)
PY
