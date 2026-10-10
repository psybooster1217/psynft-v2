#!/usr/bin/env python3
"""
Mutation testing for src/PsyNFTV2.sol (audit 2026-10, W3).

Generates single-point mutants of the contract (removed requires, flipped comparisons, dropped
modifiers, deleted state writes/events, boolean and arithmetic swaps), runs the deterministic test
suite against each one in isolated copies of the repo, and reports which mutants SURVIVED (no test
failed). A survivor is either a missing test or an equivalent mutant that needs a written reason.

Usage (from the repo root):
    python -I audit/2026-10/mutation/mutate.py [--workers 6] [--only N]

Writes audit/2026-10/mutation/results.json and results.md.
"""
import argparse, json, os, re, shutil, subprocess, sys, tempfile, time
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
SRC = os.path.join(ROOT, "src", "PsyNFTV2.sol")
OUT_DIR = os.path.dirname(os.path.abspath(__file__))
FORGE = shutil.which("forge") or os.path.expanduser("~/.foundry/bin/forge")
COPY = ["src", "test", "script", "lib", "snapshot", "foundry.toml", "remappings.txt", "foundry.lock"]

MODIFIERS = ["onlyOwner", "onlyCoreContract", "notFinalized", "nonReentrant"]
REL_SWAPS = {"<=": ["<", "=="], ">=": [">", "=="], "<": ["<=", ">="], ">": [">=", "<="], "==": ["!="], "!=": ["=="]}


def code_part(line):
    """Return the code portion of a line (strip // comments and string literals' contents)."""
    s = line.split("//")[0]
    return s


def is_comment(line):
    t = line.strip()
    return t.startswith("//") or t.startswith("*") or t.startswith("/*") or t == ""


def mutants(src):
    lines = src.split("\n")
    out = []

    def add(kind, ln, new_line, desc):
        m = lines.copy()
        m[ln] = new_line
        out.append({"kind": kind, "line": ln + 1, "desc": desc, "src": "\n".join(m)})

    # 1) require removal (also multi-line requires)
    for m in re.finditer(r"require\((?:[^;]|\n)*?\);", src):
        start = src.count("\n", 0, m.start())
        text = m.group(0)
        mutated = src[: m.start()] + "/* MUTANT: require removed */" + src[m.end():]
        out.append({"kind": "require-removed", "line": start + 1, "desc": " ".join(text.split())[:110], "src": mutated})

    for i, line in enumerate(lines):
        if is_comment(line):
            continue
        code = code_part(line)
        # strings are not mutated: blank them for matching positions
        masked = re.sub(r'"[^"]*"', lambda mm: '"' + "_" * (len(mm.group(0)) - 2) + '"', code)

        # 2) relational operator replacement
        for mm in re.finditer(r"<=|>=|==|!=|(?<![<>=])<(?![<=])|(?<![<>=\-])>(?![>=])", masked):
            op = mm.group(0)
            if op in ("<", ">") and ("mapping" in masked or "=>" in masked):
                continue
            for rep in REL_SWAPS.get(op, []):
                new = line[: mm.start()] + rep + line[mm.end():]
                add("relational", i, new, f"{op} -> {rep}: {line.strip()[:90]}")

        # 3) logical operator swap
        for mm in re.finditer(r"&&|\|\|", masked):
            rep = "||" if mm.group(0) == "&&" else "&&"
            add("logical", i, line[: mm.start()] + rep + line[mm.end():], f"{mm.group(0)} -> {rep}: {line.strip()[:90]}")

        # 4) negation removal
        for mm in re.finditer(r"!(?=[A-Za-z_(])", masked):
            add("negation", i, line[: mm.start()] + line[mm.end():], f"drop '!': {line.strip()[:90]}")

        # 5) boolean literal flip
        for mm in re.finditer(r"\b(true|false)\b", masked):
            rep = "false" if mm.group(0) == "true" else "true"
            add("bool", i, line[: mm.start()] + rep + line[mm.end():], f"{mm.group(0)} -> {rep}: {line.strip()[:90]}")

        # 6) modifier removal (function signatures)
        for mod in MODIFIERS:
            for mm in re.finditer(r"\b" + mod + r"\b(?!\s*\()", masked):
                if "modifier " in masked:
                    continue
                add("modifier-removed", i, line[: mm.start()] + line[mm.end():], f"drop {mod}: {line.strip()[:90]}")

        # 7) increment / arithmetic
        for mm in re.finditer(r"\+\+", masked):
            add("arith", i, line[: mm.start()] + "--" + line[mm.end():], f"++ -> --: {line.strip()[:90]}")
        for mm in re.finditer(r"(?<![+\-])\s\+\s(?!\+)", masked):
            add("arith", i, line[: mm.start()] + " - " + line[mm.end():], f"+ -> -: {line.strip()[:90]}")
        for mm in re.finditer(r"\+ 1\b", masked):
            add("arith", i, line[: mm.start()] + "+ 0" + line[mm.end():], f"+1 -> +0: {line.strip()[:90]}")

        # 8) numeric constants in schedule logic
        for mm in re.finditer(r"(?<![\w.])([23])(?![\w.])", masked):
            n = int(mm.group(1))
            for rep in (n - 1, n + 1):
                add("constant", i, line[: mm.start()] + str(rep) + line[mm.end():], f"{n} -> {rep}: {line.strip()[:90]}")

        # 9) statement deletion: state writes, deletes, emits
        stripped = masked.strip()
        if re.match(r"^(emit\s+\w+|delete\s+\w+|[A-Za-z_][\w\[\]\.]*\s*(\+\+|--|=|\+=|-=)\s*[^=])", stripped) and stripped.endswith(";"):
            if not re.match(r"^(uint256|address|bool|bytes|string)\b", stripped) and "return" not in stripped:
                indent = line[: len(line) - len(line.lstrip())]
                add("stmt-deleted", i, indent + "/* MUTANT: statement deleted */", f"delete: {line.strip()[:90]}")
    return out


def run_one(workdir, mutant, timeout):
    with open(os.path.join(workdir, "src", "PsyNFTV2.sol"), "w", encoding="utf-8", newline="\n") as f:
        f.write(mutant["src"])
    env = dict(os.environ)
    env.update({"FOUNDRY_FUZZ_RUNS": "64", "FOUNDRY_INVARIANT_RUNS": "24", "FOUNDRY_INVARIANT_DEPTH": "60",
                "FOUNDRY_OPTIMIZER": "false"})
    t0 = time.time()
    try:
        p = subprocess.run([FORGE, "test", "--no-match-path", "test/*.fork.t.sol"], cwd=workdir, env=env,
                           capture_output=True, text=True, timeout=timeout)
        out = p.stdout + p.stderr
        if "Compiler run failed" in out or "Compilation failed" in out:
            status = "stillborn"  # does not compile: not a meaningful mutant
        elif p.returncode != 0:
            status = "killed"
        else:
            status = "SURVIVED"
        killers = sorted(set(re.findall(r"\[FAIL[^\]]*\]\s*(\w+)", out)))[:6]
    except subprocess.TimeoutExpired:
        status, killers = "killed", ["<timeout>"]
    return status, killers, round(time.time() - t0, 1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--only", type=int, default=0, help="run only the first N mutants (smoke test)")
    ap.add_argument("--timeout", type=int, default=600)
    args = ap.parse_args()

    src = open(SRC, encoding="utf-8").read()
    ms = mutants(src)
    # de-duplicate identical mutant sources
    seen, uniq = set(), []
    for m in ms:
        h = hash(m["src"])
        if h not in seen and m["src"] != src:
            seen.add(h)
            uniq.append(m)
    ms = uniq[: args.only] if args.only else uniq
    print(f"{len(ms)} mutants, {args.workers} workers", flush=True)

    base = tempfile.mkdtemp(prefix="psynft-mut-")
    dirs = []
    for w in range(args.workers):
        d = os.path.join(base, f"w{w}")
        os.makedirs(d)
        for item in COPY:
            s = os.path.join(ROOT, item)
            if os.path.isdir(s):
                shutil.copytree(s, os.path.join(d, item), ignore=shutil.ignore_patterns(".git", "node_modules"))
            elif os.path.exists(s):
                shutil.copy2(s, os.path.join(d, item))
        dirs.append(d)

    # Baseline: the UNMUTATED contract must pass in the copy, or every mutant would look
    # "stillborn"/"killed" for reasons unrelated to the mutation.
    status, killers, _ = run_one(dirs[0], {"src": src}, args.timeout)
    if status != "SURVIVED":
        print(f"ABORT: baseline (unmutated) run is '{status}' {killers} — fix the copy/test setup first", flush=True)
        sys.exit(2)

    results = [None] * len(ms)

    def worker(w):
        for idx in range(w, len(ms), args.workers):
            status, killers, secs = run_one(dirs[w], ms[idx], args.timeout)
            m = ms[idx]
            results[idx] = {"id": idx, "kind": m["kind"], "line": m["line"], "desc": m["desc"], "status": status,
                            "killed_by": killers, "seconds": secs}
            print(f"[{idx + 1}/{len(ms)}] {status:9} L{m['line']:<4} {m['kind']:16} {m['desc'][:80]}", flush=True)

    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        list(ex.map(worker, range(args.workers)))

    shutil.rmtree(base, ignore_errors=True)
    valid = [r for r in results if r["status"] != "stillborn"]
    killed = [r for r in valid if r["status"] == "killed"]
    survived = [r for r in valid if r["status"] == "SURVIVED"]
    summary = {"total": len(results), "valid": len(valid), "killed": len(killed), "survived": len(survived),
               "stillborn": len(results) - len(valid),
               "score": round(100 * len(killed) / max(1, len(valid)), 1)}
    json.dump({"summary": summary, "results": results}, open(os.path.join(OUT_DIR, "results.json"), "w", encoding="utf-8"), indent=1)
    with open(os.path.join(OUT_DIR, "results.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write(f"# Mutation testing — src/PsyNFTV2.sol\n\n")
        f.write(f"**Score: {summary['score']}%** — {summary['killed']} of {summary['valid']} valid mutants killed "
                f"({summary['stillborn']} did not compile and are excluded).\n\n")
        f.write("## Survivors\n\n| # | Line | Kind | Mutation |\n|---|---|---|---|\n")
        for r in survived:
            f.write(f"| {r['id']} | {r['line']} | {r['kind']} | `{r['desc'].replace('|', '/')}` |\n")
        f.write("\n## By kind\n\n| Kind | Valid | Killed |\n|---|---|---|\n")
        kinds = sorted(set(r["kind"] for r in valid))
        for k in kinds:
            v = [r for r in valid if r["kind"] == k]
            f.write(f"| {k} | {len(v)} | {sum(1 for r in v if r['status'] == 'killed')} |\n")
    print(json.dumps(summary), flush=True)


if __name__ == "__main__":
    main()
