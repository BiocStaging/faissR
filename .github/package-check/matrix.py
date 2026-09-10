#!/usr/bin/env python3
"""Run the same source archive on configured native/container hosts.

Configuration is trusted local operator input; never put private keys in it.
Targets run sequentially. Failure is recorded and does not prevent later tests.
"""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys


def ps_quote(value):
    return "'" + str(value).replace("'", "''") + "'"


def powershell(script):
    encoded = base64.b64encode(script.encode("utf-16-le")).decode("ascii")
    return "powershell -NoProfile -ExecutionPolicy Bypass -EncodedCommand " + encoded


def run(argv, log, check=True):
    log.write("COMMAND " + shlex.join(argv) + "\n")
    log.flush()
    proc = subprocess.run(argv, stdout=log, stderr=subprocess.STDOUT, check=False)
    if check and proc.returncode:
        raise RuntimeError(f"Command exited {proc.returncode}; see controller.log")
    return proc.returncode


def remote(target, command, log, check=True):
    return run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=20",
                "-o", "ServerAliveInterval=30", "-o", "ServerAliveCountMax=3",
                *target.get("ssh_options", []), target["host"], command], log, check)


def copy(target, src, dst, log, recursive=False):
    return run(["scp", "-o", "BatchMode=yes", "-o", "ConnectTimeout=20",
                "-o", "ServerAliveInterval=30", "-o", "ServerAliveCountMax=3",
                *target.get("ssh_options", []),
                *(["-r"] if recursive else []), str(src), str(dst)], log)


def execute(target, archive, output, harness, digest, commit):
    name = target["name"]
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", name):
        raise ValueError("Target names must contain only letters, digits, _, . or -")
    dest = output / name
    dest.mkdir()
    kind = target["kind"]
    with (dest / "controller.log").open("w") as log:
        if kind == "macos":
            code = run(["bash", str(harness / "macos.sh"), str(archive),
                        str(dest / "results")], log, check=False)
        else:
            root = target["root"].rstrip("/\\")
            # A new remote directory prevents old results being mistaken for this run.
            folder = root + "/runs/" + output.name + "-" + name
            transfer_folder = target.get("scp_root", root).rstrip("/\\") + "/runs/" + output.name + "-" + name
            if kind == "linux":
                remote(target, "test -r " + shlex.quote(target["image"]), log)
                remote(target, "test ! -e " + shlex.quote(folder) +
                       " && mkdir -p " + shlex.quote(folder + "/harness"), log)
            elif kind == "windows":
                remote(target, powershell(
                    f"$ErrorActionPreference='Stop'; if(Test-Path {ps_quote(folder)})"
                    "{throw 'Run directory already exists'}; "
                    f"New-Item -ItemType Directory -Force {ps_quote(folder)} | Out-Null; "
                    f"New-Item -ItemType Directory -Force {ps_quote(folder+'/harness')} | Out-Null"), log)
            else:
                raise ValueError("Unknown host kind: " + kind)
            copy(target, str(harness) + "/.", target["host"] + ":" + transfer_folder + "/harness/", log, True)
            remote_archive = folder + "/" + archive.name
            copy(target, archive, target["host"] + ":" + transfer_folder + "/" + archive.name, log)
            if kind == "linux":
                command = ("printf '%s  %s\\n' " + shlex.quote(digest) + " " +
                           shlex.quote(remote_archive) + " | sha256sum -c - && " +
                           "PACKAGE_TEST_COMMIT=" + shlex.quote(commit) + " bash " +
                           shlex.join([folder + "/harness/linux/run.sh", target["image"],
                                       remote_archive, folder + "/results", "functional"]))
                code = remote(target, command, log, check=False)
            else:
                command = ("$ErrorActionPreference='Stop'; "
                           f"if((Get-FileHash {ps_quote(remote_archive)}).Hash -ne {ps_quote(digest)})"
                           "{throw 'Source checksum mismatch'}; "
                           f"$env:PACKAGE_TEST_COMMIT={ps_quote(commit)}; & " +
                           ps_quote(folder + "/harness/windows/run.ps1") +
                           " -Archive " + ps_quote(remote_archive) +
                           " -Output " + ps_quote(folder + "/results") +
                           " -Profile " + ps_quote(target.get("profile", "functional")) +
                           " -FaissHome " + ps_quote(target.get("faiss_home", "")) +
                           " -DependencyLibrary " + ps_quote(target.get("dependency_library", "")) +
                           " -RHome " + ps_quote(target["r_home"]) +
                           " -Rtools " + ps_quote(target["rtools"]) + "; exit $LASTEXITCODE")
                code = remote(target, powershell(command), log, check=False)
            # Copy complete artifacts, including the tested private installation.
            # This is intentionally read-only; no remote cleanup is implicit.
            copy(target, target["host"] + ":" + transfer_folder + "/results", dest, log, True)
    return {"target": name, "exit_code": code,
            "profile": target.get("profile", "functional"),
            "status": "PASS" if code == 0 else "FAIL"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("config", type=Path)
    parser.add_argument("archive", type=Path)
    parser.add_argument("output", type=Path, help="New local directory")
    parser.add_argument("--commit", required=True, help="Source commit or explicit dirty identifier")
    parser.add_argument("--only", help="Comma-separated target names for a focused rerun")
    opts = parser.parse_args()
    archive = opts.archive.resolve(strict=True)
    output = opts.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    source_dir = output / "source"
    source_dir.mkdir()
    snapshot = source_dir / archive.name
    shutil.copyfile(archive, snapshot)
    archive = snapshot
    harness = output / "harness"
    shutil.copytree(Path(__file__).resolve().parent, harness,
                    ignore=shutil.ignore_patterns("__pycache__"))
    with archive.open("rb") as handle:
        digest = hashlib.file_digest(handle, "sha256").hexdigest()
    os.environ["PACKAGE_TEST_COMMIT"] = opts.commit
    (output / "source.sha256").write_text(digest + "  " + archive.name + "\n")
    targets = json.loads(opts.config.read_text())["targets"]
    if opts.only:
        names = set(opts.only.split(","))
        known = {x["name"] for x in targets}
        if not names <= known:
            parser.error("Unknown targets: " + ", ".join(sorted(names - known)))
        targets = [x for x in targets if x["name"] in names]
    results = []
    for target in targets:
        print("Testing", target["name"], flush=True)
        try:
            result = execute(target, archive, output, harness,
                             digest, opts.commit)
        except (OSError, RuntimeError, ValueError) as exc:
            result = {"target": target["name"], "status": "BLOCKED", "error": str(exc)}
        results.append(result)
        (output / "matrix.json").write_text(json.dumps(results, indent=2) + "\n")
        print(result, flush=True)
    return int(any(x["status"] != "PASS" for x in results))


if __name__ == "__main__":
    sys.exit(main())
