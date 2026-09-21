#!/usr/bin/env python3
"""Per-agent context telemetry, read straight from the subagent transcripts.

The activity ledger only sees the Read tool. Agents overwhelmingly read with
Bash (cat/sed/grep), so the ledger undercounts badly. The transcripts record
every tool call and every usage block, so they are the honest source.

Emits results/empirical.tsv:
    arm  task  rep  peak_ctx  new_ctx  total_input  output  turns  tools  files
"""
import json, os, sys, re, glob

WF = {
    "a": "wf_bc34564e-f5a",
    "b": "wf_f23a02ee-c31",
}
ROOT = os.path.dirname(os.path.abspath(__file__))
BASE = ("/root/.claude/projects/-workspace-context-kit/"
        "da3cd5a2-f189-5ac2-b396-7d6f686ae305/subagents/workflows")

PATH_RE = re.compile(r'[\w./-]+\.(?:ts|md|sql|json|js)\b')


def labels(wfdir):
    """agentId -> label, from the workflow journal."""
    out = {}
    jp = os.path.join(wfdir, "journal.jsonl")
    if not os.path.exists(jp):
        return out
    for line in open(jp):
        try:
            o = json.loads(line)
        except Exception:
            continue
        if o.get("type") == "started" and o.get("agentId"):
            out[o["agentId"]] = o.get("label", "")
    return out


def scan(path):
    """One transcript -> usage totals, tool count, distinct project files touched."""
    peak = 0
    new_ctx = 0
    total_in = 0
    out_tok = 0
    turns = 0
    tools = 0
    files = set()
    for line in open(path):
        line = line.strip()
        if not line:
            continue
        try:
            o = json.loads(line)
        except Exception:
            continue
        msg = o.get("message") or {}
        if not isinstance(msg, dict):
            continue
        u = msg.get("usage")
        if u:
            turns += 1
            ctx = (u.get("input_tokens", 0)
                   + u.get("cache_creation_input_tokens", 0)
                   + u.get("cache_read_input_tokens", 0))
            peak = max(peak, ctx)
            total_in += ctx
            new_ctx += u.get("cache_creation_input_tokens", 0)
            out_tok += u.get("output_tokens", 0)
        content = msg.get("content")
        if isinstance(content, list):
            for b in content:
                if not isinstance(b, dict) or b.get("type") != "tool_use":
                    continue
                tools += 1
                inp = b.get("input") or {}
                blob = " ".join(str(v) for v in inp.values() if isinstance(v, str))
                for m in PATH_RE.findall(blob):
                    # keep project-relative tails only; drop the run prefix so
                    # the same file in different runs compares equal
                    m = re.sub(r'^.*?/runs/t\d-[ab]-r\d/', '', m)
                    if m.startswith(('src/', 'tests/', 'docs/', 'knowledge/',
                                     '.claude/')) or m.endswith('CLAUDE.md'):
                        files.add(m)
    return peak, new_ctx, total_in, out_tok, turns, tools, files


def main():
    rows = []
    for arm, wf in WF.items():
        wfdir = os.path.join(BASE, wf)
        lab = labels(wfdir)
        for tp in sorted(glob.glob(os.path.join(wfdir, "agent-*.jsonl"))):
            aid = os.path.basename(tp)[len("agent-"):-len(".jsonl")]
            label = lab.get(aid, "")
            m = re.match(r'^(t\d)-r(\d)$', label)
            if not m:
                sys.stderr.write("skip unlabelled agent %s (%r)\n" % (aid, label))
                continue
            task, rep = m.group(1), m.group(2)
            peak, new_ctx, tin, out, turns, tools, files = scan(tp)
            rows.append((arm, task, rep, peak, new_ctx, tin, out, turns,
                         tools, len(files), sorted(files)))

    rows.sort(key=lambda r: (r[1], r[0], r[2]))
    os.makedirs(os.path.join(ROOT, "results"), exist_ok=True)
    tsv = os.path.join(ROOT, "results", "empirical.tsv")
    with open(tsv, "w") as fh:
        fh.write("arm\ttask\trep\tpeak_ctx\tnew_ctx\ttotal_input\toutput\t"
                 "turns\ttools\tfiles\n")
        for r in rows:
            fh.write("\t".join(str(x) for x in r[:10]) + "\n")

    fl = os.path.join(ROOT, "results", "files-read.tsv")
    with open(fl, "w") as fh:
        fh.write("arm\ttask\trep\tfile\n")
        for r in rows:
            for f in r[10]:
                fh.write("%s\t%s\t%s\t%s\n" % (r[0], r[1], r[2], f))

    print("wrote %s (%d runs)" % (tsv, len(rows)))
    for r in rows:
        print("  %s %s r%s  peak=%-7d new=%-7d tools=%-3d files=%d"
              % (r[0], r[1], r[2], r[3], r[4], r[8], r[9]))


if __name__ == "__main__":
    main()
