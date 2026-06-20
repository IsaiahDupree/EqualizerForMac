#!/usr/bin/env python3
"""safari.py — drive Safari's front document via `do JavaScript`, with the deepdom.js shadow-piercing
library auto-injected. The JS payload is base64-encoded and run via eval(atob(...)) so there is zero
AppleScript string-escaping pain (newlines, quotes, unicode all pass through cleanly).

CLI:
  goto <url>                 navigate the front document
  fields                     JSON list of every interactive control (deep), each with a stable id
  find <substr>              fields whose label/text contains <substr> (case-insensitive)
  set <id> <value>           set an input/textarea value (React-aware)
  check <id> [on|off]        toggle a checkbox/switch to a state
  click <id>                 click the element with that id
  clicktext <text>           click the first element whose exact text matches
  pick <id> <optionText>     choose a <select>/combobox option by text
  waitfor <substr> [secs]    poll until visible text contains <substr> (default 20s)
  eval <expr>                run an arbitrary JS expression (with __asc available) and print the result

Used by pipeline.py for the web-only App Store Connect steps (create app record, pricing, submit).
"""
import base64, json, subprocess, sys, time, os

LIB = open(os.path.join(os.path.dirname(__file__), "deepdom.js")).read()

def run(expr, inject=True):
    payload = (LIB + "\n" if inject else "") + "String(" + expr + ")"
    b64 = base64.b64encode(payload.encode()).decode()
    script = 'tell application "Safari" to do JavaScript "eval(atob(\\"%s\\"))" in front document' % b64
    r = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(r.stderr.strip())
    return r.stdout.strip()

def run_json(expr):
    return json.loads(run("JSON.stringify(" + expr + ")"))

def goto(url):
    subprocess.run(["osascript", "-e",
        'tell application "Safari" to set URL of front document to "%s"' % url], check=True)

def jarg(s):  # JS string literal
    return json.dumps(s)

def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "fields"
    a = sys.argv[2:]
    if cmd == "goto":
        goto(a[0]); print("→", a[0])
    elif cmd == "fields":
        for f in run_json("__asc.fields()"):
            opt = (" opts=" + "/".join(f["options"])[:60]) if f.get("options") else ""
            print(f'{f["id"]:>3} {f["tag"]:<9}{f["type"]:<11} [{f["label"]}] {f["text"]}'
                  f'{" ✓" if f.get("checked") else ""}{" (disabled)" if f.get("disabled") else ""}{opt}')
    elif cmd == "find":
        q = a[0].lower()
        for f in run_json("__asc.fields()"):
            if q in (f["label"] + " " + f["text"]).lower():
                print(f'{f["id"]:>3} {f["tag"]:<9}{f["type"]:<11} [{f["label"]}] {f["text"]}')
    elif cmd == "set":
        print(run("__asc.set(%s,%s)" % (a[0], jarg(a[1]))))
    elif cmd == "check":
        on = "true" if (len(a) < 2 or a[1] != "off") else "false"
        print(run("__asc.check(%s,%s)" % (a[0], on)))
    elif cmd == "click":
        print(run("__asc.click(%s)" % a[0]))
    elif cmd == "clicktext":
        print(run("__asc.clickText(%s)" % jarg(a[0])))
    elif cmd == "pick":
        print(run("__asc.pick(%s,%s)" % (a[0], jarg(a[1]))))
    elif cmd == "waitfor":
        needle, secs = a[0], int(a[1]) if len(a) > 1 else 20
        for _ in range(secs):
            if run("__asc.hasText(%s)" % jarg(needle)) == "true":
                print("found:", needle); return
            time.sleep(1)
        print("TIMEOUT waiting for:", needle); sys.exit(1)
    elif cmd == "eval":
        print(run(a[0]))
    else:
        print(__doc__)

if __name__ == "__main__":
    main()
