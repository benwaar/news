#!/usr/bin/env python3
import json
import subprocess
import sys

def pick_base():
    for cand in ["origin/dev", "origin/develop", "origin/main", "origin/master"]:
        try:
            subprocess.run(["git", "show-ref", "--verify", "--quiet", f"refs/remotes/{cand}"], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return cand
        except subprocess.CalledProcessError:
            continue
    raise SystemExit("No dev-like base branch found (origin/dev, origin/develop, origin/main, origin/master).")

def safe(o):
    return o if isinstance(o, dict) else {}

def diff(name, b, h):
    added=[]; removed=[]; changed=[]
    for k,v in h.items():
        if k not in b:
            added.append((k,v))
        elif b[k] != v:
            changed.append((k,b[k],v))
    for k,v in b.items():
        if k not in h:
            removed.append((k,v))
    print(f"\n=== {name} ===")
    if not added and not removed and not changed:
        print("No changes"); return
    if changed:
        print("Updated:")
        for k,f,t in sorted(changed):
            print(f"  - {k}: {f} -> {t}")
    if added:
        print("Added:")
        for k,v in sorted(added):
            print(f"  - {k}: {v}")
    if removed:
        print("Removed:")
        for k,v in sorted(removed):
            print(f"  - {k}: {v}")

def main():
    try:
        subprocess.run(["git", "fetch", "origin", "--prune"], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        base = None
        if "--base" in sys.argv:
            base = sys.argv[sys.argv.index("--base")+1]
        else:
            base = pick_base()
        base_json = subprocess.check_output(["git", "show", f"{base}:package.json"]).decode()
        head_json = subprocess.check_output(["git", "show", "HEAD:package.json"]).decode()
        base = base
        bj = json.loads(base_json)
        hj = json.loads(head_json)
        print(f"Base: {base}")
        print("Dependency changes (HEAD vs base):")
        for sec in ["dependencies","devDependencies","peerDependencies","optionalDependencies"]:
            diff(sec, safe(bj.get(sec)), safe(hj.get(sec)))
    except Exception as e:
        print(f"Failed to compute dependency changes: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
