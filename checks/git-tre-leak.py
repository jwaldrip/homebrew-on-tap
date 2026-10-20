#!/usr/bin/env python3
"""PATH check for jwaldrip/on-tap/git.

Proves three things about the `git` that a shell on this Mac resolves from
PATH, the same one omp agents run:

  identity  it is the jwaldrip/on-tap keg and carries darwin_regexec_buf,
            the upstream macOS TRE regexec leak workaround
  bounded   `git grep -E <rev> -- <paths with binary files>` in
            phoneware/monorepo finishes under a memory cap in a UTF-8 locale
  same      that UTF-8 run prints byte-identical matches to the C locale run,
            where TRE never sees an invalid byte

Every run is polled and killed past CAP_BYTES, so pointing this at an
unpatched git is safe: it fails at the cap instead of tripping memory-guard.
Exit 0 and a final PASS line mean green; anything else is red.
"""

import ctypes
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

REPO = Path.home() / "dev/src/github.com/phoneware/monorepo"
# Pinned so the expected line counts never move. Reachable from phoneware/monorepo main.
REV = "648289ddc594c61f5e70c532b308fc178db8b835"
EXPECTED_GIT = "/opt/homebrew/bin/git"
TAP = "jwaldrip/on-tap"
MARKER = "_darwin_regexec_buf"
UTF8 = "en_US.UTF-8"
CAP_BYTES = 4 * 10**9  # far below memory-guard's 24 GB kill line
BOUND_BYTES = 1 * 10**9  # the patched build peaks near 0.18 GB on these probes
TIMEOUT_S = 120

PROBES = [
    # The command omp agents ran when the leak was found (21.7 GB in under 1 s).
    (
        "agents",
        r"metaswitch[-_]mcp[-_](sweep|line[-_]audit[-_]sweep|ns[-_]api[-_]key|ns[-_]read[-_]key)"
        r"|drive\.googleapis\.com|sheets\.googleapis\.com|internal/line-audit/sweep",
        ["infra/", "scripts/", "docs/"],
        41,
    ),
    # Chunk ids inside wav and png files, so binary files really produce matches.
    (
        "binary",
        r"data|LIST|INFO|RIFF|WAVE|IHDR|IDAT|IEND",
        ["docs/telzino/evidence/", "docs/reports/"],
        905,
    ),
]


class RUsageInfo(ctypes.Structure):
    _fields_ = [("uuid", ctypes.c_uint8 * 16)] + [(f"f{i}", ctypes.c_uint64) for i in range(40)]


LIBPROC = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)


def footprint(pid):
    usage = RUsageInfo()
    if LIBPROC.proc_pid_rusage(pid, 4, ctypes.byref(usage)) != 0:  # RUSAGE_INFO_V4
        return 0
    return usage.f7  # ri_phys_footprint


def run_capped(argv, locale):
    env = dict(os.environ, LC_ALL=locale)
    with tempfile.TemporaryFile() as out:
        start = time.monotonic()
        proc = subprocess.Popen(argv, cwd=REPO, env=env, stdout=out, stderr=subprocess.DEVNULL)
        peak, outcome = 0, "exited"
        while proc.poll() is None:
            peak = max(peak, footprint(proc.pid))
            if peak > CAP_BYTES:
                proc.kill()
                outcome = "KILLED_AT_CAP"
                break
            if time.monotonic() - start > TIMEOUT_S:
                proc.kill()
                outcome = "TIMEOUT"
                break
            time.sleep(0.05)
        proc.wait()
        secs = time.monotonic() - start
        out.seek(0)
        data = out.read()
    return outcome, proc.returncode, peak, secs, data


def check_identity():
    git = shutil.which("git")
    if git is None:
        print("identity  git not found on PATH  FAIL")
        return None, False
    real = Path(git).resolve()
    receipt = real.parent.parent / "INSTALL_RECEIPT.json"
    tap = json.loads(receipt.read_text())["source"].get("tap") if receipt.is_file() else None
    symbols = subprocess.run(["nm", "-U", str(real)], capture_output=True, text=True).stdout
    marker = "present" if MARKER in symbols else "absent"
    version = subprocess.run([git, "--version"], capture_output=True, text=True).stdout.strip()
    ok = git == EXPECTED_GIT and tap == TAP and marker == "present"
    print(f"identity  git={git} keg={real.parent.parent} version={version!r} tap={tap} "
          f"marker={MARKER}:{marker}  {'OK' if ok else 'FAIL'}")
    return git, ok


def check_probe(git, name, pattern, paths, expected_lines):
    argv = [git, "--no-pager", "grep", "-n", "-E", pattern, REV, "--", *paths]
    u_out, u_rc, u_peak, u_secs, u_data = run_capped(argv, UTF8)
    c_out, c_rc, _, _, c_data = run_capped(argv, "C")
    bounded = u_out == "exited" and u_rc == 0 and u_peak < BOUND_BYTES
    same = c_out == "exited" and c_rc == 0 and u_data == c_data
    lines = c_data.splitlines()
    binaries = sum(1 for line in lines if line.startswith(b"Binary file "))
    ok = bounded and same and len(lines) == expected_lines
    print(f"{name:<8}  {UTF8}: {u_out} rc={u_rc} peak={u_peak / 1e9:.2f}GB secs={u_secs:.1f} "
          f"sha256={hashlib.sha256(u_data).hexdigest()[:16]} | C: {c_out} rc={c_rc} "
          f"sha256={hashlib.sha256(c_data).hexdigest()[:16]} lines={len(lines)}/{expected_lines} "
          f"binary_files={binaries} same={'yes' if same else 'no'}  {'OK' if ok else 'FAIL'}")
    return ok


def main():
    if not (REPO / ".git").exists():
        print(f"repo      {REPO} missing  FAIL")
        print("FAIL")
        return 1
    git, ok = check_identity()
    if git is None:
        print("FAIL")
        return 1
    for name, pattern, paths, expected_lines in PROBES:
        ok = check_probe(git, name, pattern, paths, expected_lines) and ok
    print("PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
