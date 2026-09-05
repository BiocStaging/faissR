"""Check submission-source references, assets, version labels, and dependencies."""

from pathlib import Path
import re
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
version = re.search(r"^Version:\s*(\S+)", (ROOT / "DESCRIPTION").read_text(),
                    re.M).group(1)
bib = set(re.findall(r"@\w+\{([^,]+),", (HERE / "faissR_jss.bib").read_text()))
errors = []
for name in ("faissR_jss.tex", "faissR_jss_supplement.tex"):
    text = (HERE / name).read_text()
    for old in set(re.findall(r"0\.99\.\d+", text)) - {version}:
        errors.append(f"{name}: obsolete package version {old}")
    for token in ("nabor", "mlbench", "submission blocker", "planned experiments"):
        if token in text.lower():
            errors.append(f"{name}: unwanted narrative {token}")
    labels = re.findall(r"\\label\{([^}]+)\}", text)
    if len(labels) != len(set(labels)):
        errors.append(f"{name}: duplicate labels")
    for ref in re.findall(r"\\(?:eqref|ref)\{([^}]+)\}", text):
        if ref not in labels:
            errors.append(f"{name}: unresolved reference {ref}")
    for cites in re.findall(r"\\cite\w*\{([^}]+)\}", text):
        for cite in cites.split(","):
            if cite.strip() not in bib:
                errors.append(f"{name}: unresolved citation {cite}")
    assets = re.findall(r"\\(?:includegraphics|input)(?:\[[^\]]*\])?\{([^}]+)\}",
                        text)
    for asset in assets:
        path = HERE / asset
        if not path.is_file():
            errors.append(f"{name}: missing asset {asset}")
        elif (ROOT / ".git").exists() and subprocess.run(
            ["git", "check-ignore", "-q", str(path)],
            cwd=ROOT,
            stderr=subprocess.DEVNULL,
        ).returncode == 0:
            errors.append(f"{name}: asset excluded from GitHub {asset}")
for name in ("README.md", "docs/installation.md", "vignettes/installation.Rmd"):
    for old in set(re.findall(r"faissR_(0\.99\.\d+)\.tar\.gz",
                              (ROOT / name).read_text())) - {version}:
        errors.append(f"{name}: obsolete installation tarball {old}")

main = (HERE / "faissR_jss.tex").read_text()
supplement = (HERE / "faissR_jss_supplement.tex").read_text()
required_main = (
    "supports reusable CPU indexes",
    "label{tab:tuned-hnsw}",
    "label{tab:comprehensive-r}",
    "recorded outcomes for all 216 design tasks",
)
for phrase in required_main:
    if phrase not in main:
        errors.append(f"faissR_jss.tex: missing reviewed wording {phrase}")
if not re.search(r"not a comparison with a reusable exact\s+index", main):
    errors.append("faissR_jss.tex: rebuilt-Flat scope is not explicit")
if "label{tab:paired-time}" in main:
    errors.append("faissR_jss.tex: secondary CUDA selector table remains in main text")
if "label{tab:supp-cuda-paired}" not in supplement:
    errors.append("faissR_jss_supplement.tex: missing moved CUDA selector table")
if supplement.count("includegraphics[width=0.94\\textwidth]{fig_comprehensive_r_log_ratio.pdf}") != 1:
    errors.append("faissR_jss_supplement.tex: comprehensive figure is missing or duplicated")
if errors:
    raise SystemExit("\n".join(errors))
print(f"SUBMISSION SOURCE AUDIT PASSED: faissR {version}")
