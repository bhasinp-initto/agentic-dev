#!/usr/bin/env bash
# query-checklist.sh — return top-K most-relevant checklist.yaml rules for a query.
#
# Usage: query-checklist.sh "<query text>" [-k N]
#   Default K=5.
#
# Output: JSONL — one ranked entry per line, in descending relevance order. Fields:
#   { "rank": N, "score": <float>, "date", "incident_ref", "rule", "caught_by" }
#
# Ranking: bag-of-words cosine similarity over tokenized rule text vs query. No
# external ML dependencies (pure stdlib + pyyaml). Stopword-filtered. Works well
# for N<200 entries; upgrade to real embeddings if quality drops with scale.
#
# Exit codes:
#   0 — success (may print 0 entries if checklist is empty or no matches)
#   1 — checklist.yaml missing
#   2 — usage error
set -euo pipefail

QUERY="${1:-}"
if [[ -z "$QUERY" ]]; then
  echo "Usage: query-checklist.sh \"<query text>\" [-k N]" >&2
  exit 2
fi
shift

K=5
while [[ $# -gt 0 ]]; do
  case "$1" in
    -k|--top-k) K="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

CHECKLIST=".claude/agentic/checklist.yaml"
if [[ ! -f "$CHECKLIST" ]]; then
  echo "ERROR: checklist not found at $CHECKLIST" >&2
  exit 1
fi

export QUERY CHECKLIST K
python3 - <<'PY'
import os, re, math, json, sys
from collections import Counter

try:
    import yaml
except ImportError:
    sys.stderr.write("ERROR: pyyaml not installed; pip install pyyaml\n")
    sys.exit(2)

QUERY = os.environ["QUERY"]
CHECKLIST = os.environ["CHECKLIST"]
K = int(os.environ["K"])

# Small English stopword set (we don't import nltk to keep dependencies minimal).
STOPWORDS = set("""
a an the and or but in on at to for of with from by as is are was were be been being
have has had do does did not no this that these those it its they them their there
will would should could may might shall can if then else when while where what which
who whom how about after before above below up down out over under again further once
also too very just only some any all most many much more less few several into onto
""".split())

def tokenize(text: str):
    """Lowercase + alnum tokenize + stopword + length>2 filter."""
    return [t for t in re.findall(r"[A-Za-z0-9_]+", text.lower())
            if t not in STOPWORDS and len(t) > 2]

def bow(text: str) -> Counter:
    return Counter(tokenize(text))

def cosine(a: Counter, b: Counter) -> float:
    common = set(a) & set(b)
    if not common:
        return 0.0
    num = sum(a[k] * b[k] for k in common)
    da = math.sqrt(sum(v * v for v in a.values()))
    db = math.sqrt(sum(v * v for v in b.values()))
    if da == 0 or db == 0:
        return 0.0
    return num / (da * db)

# Load checklist
with open(CHECKLIST) as f:
    data = yaml.safe_load(f) or {}
entries = (data.get("entries") or []) if isinstance(data, dict) else []

if not entries:
    sys.exit(0)  # silent: no matches

query_bow = bow(QUERY)
if not query_bow:
    sys.exit(0)  # query had no usable tokens

ranked = []
for e in entries:
    rule = e.get("rule", "")
    score = cosine(query_bow, bow(rule))
    if score > 0:
        ranked.append((score, e))

ranked.sort(key=lambda t: t[0], reverse=True)
top = ranked[:K]

for rank, (score, e) in enumerate(top, start=1):
    out = {
        "rank": rank,
        "score": round(score, 4),
        "date": e.get("date"),
        "incident_ref": e.get("incident_ref"),
        "rule": e.get("rule"),
        "caught_by": e.get("caught_by"),
    }
    print(json.dumps(out))
PY
