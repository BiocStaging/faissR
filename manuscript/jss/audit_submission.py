"""Check submission-source references, assets, version labels, and dependencies."""

from pathlib import Path
import re
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
version = re.search(r"^Version:\s*(\S+)", (ROOT / "DESCRIPTION").read_text(),
                    re.M).group(1)
bib_entries = re.findall(
    r"@\w+\{([^,]+),", (HERE / "faissR_jss.bib").read_text()
)
bib = set(bib_entries)
errors = []
for key in sorted({key for key in bib_entries if bib_entries.count(key) > 1}):
    errors.append(f"faissR_jss.bib: duplicate bibliography key {key}")
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
    reference_labels = set(labels)
    for prefix, document in re.findall(
        r"\\externaldocument\[([^]]*)\]\{([^}]+)\}", text
    ):
        external = (HERE / document).with_suffix(".tex")
        reference_labels.update(
            prefix + label for label in re.findall(
                r"\\label\{([^}]+)\}", external.read_text()
            )
        )
    for ref in re.findall(r"\\(?:eqref|ref)\{([^}]+)\}", text):
        if ref not in reference_labels:
            errors.append(f"{name}: unresolved reference {ref}")
    for table in re.findall(
        r"\\begin\{table\}.*?\\end\{table\}", text, flags=re.S
    ):
        if table.index(r"\caption{") < table.rfind(r"\end{tabular"):
            errors.append(f"{name}: table caption precedes its table")
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
evidence_matrix = (
    ROOT
    / "benchmark_scripts/jss_reproduction/validation/PUBLICATION_EVIDENCE_MATRIX.md"
).read_text()
deliverables = (HERE / "README_DELIVERABLES.md").read_text()
cited = set()
for source in (main, supplement):
    for group in re.findall(r"\\cite\w*\{([^}]+)\}", source):
        cited.update(key.strip() for key in group.split(","))
for key in sorted(bib - cited):
    errors.append(f"faissR_jss.bib: unused bibliography key {key}")
abstract = main[main.index(r"\Abstract{"):main.index(r"\Keywords{")]
if "dense double- or single-precision matrices" in abstract:
    errors.append(
        "faissR_jss.tex: abstract conflates accepted input and search precision"
    )
if "FAISS and cuVS operate on float32 coordinates" not in abstract:
    errors.append("faissR_jss.tex: abstract does not state FAISS/cuVS precision")
focus_sentence = (
    "We focus on nearest-neighbor search. Prediction by kNN and k-means "
    "clustering"
)
if main.count(focus_sentence) != 1:
    errors.append("faissR_jss.tex: interface-scope sentence is missing or duplicated")
for stale in (
    "Pending; not in the current analysed archive",
    "no Pareto or fitted ratio is currently admissible",
    "functional reuse only in the current article",
):
    if stale in evidence_matrix:
        errors.append(f"PUBLICATION_EVIDENCE_MATRIX.md: stale status {stale}")
if re.search(r"currently\s+\d+\s+pages", deliverables):
    errors.append("README_DELIVERABLES.md: hard-coded page count can become stale")
required_main = (
    "label{tab:tuned-hnsw}",
    "label{tab:comprehensive-r}",
)
for phrase in required_main:
    if phrase not in main:
        errors.append(f"faissR_jss.tex: missing reported result {phrase}")

for kind in ("tab", "fig"):
    expected = re.findall(rf"\\label\{{({kind}:[^}}]+)\}}", supplement)
    for name, source, prefix in (
        ("faissR_jss.tex", main, "supp-"),
        ("faissR_jss_supplement.tex", supplement, ""),
    ):
        references = re.findall(
            rf"\\ref\{{{prefix}({kind}:[^}}]+)\}}", source
        )
        first_mentions = list(dict.fromkeys(references))
        for label in set(expected) - set(first_mentions):
            errors.append(f"{name}: uncited supplementary asset {label}")
        if first_mentions != expected:
            errors.append(
                f"{name}: supplementary {kind} first citations are out of "
                f"order; expected {expected}, found {first_mentions}"
            )
        if not prefix:
            for label in first_mentions:
                if source.index(f"\\ref{{{label}}}") > source.index(
                    f"\\label{{{label}}}"
                ):
                    errors.append(f"{name}: {label} is introduced after its display")

# Product names, package names, accession identifiers, language names, and
# literal code identifiers are not acronyms that can be expanded responsibly.
# Require definitions for every prose abbreviation that is used editorially.
acronym_requirements = {
    "faissR_jss.tex": (
        "Facebook Artificial Intelligence Similarity Search (FAISS)",
        "Compute Unified Device Architecture (CUDA)",
        "central processing unit (CPU)",
        "graphics processing unit (GPU)",
        "inverted-file (IVF)",
        "product-quantization (PQ)",
        "approximate nearest-neighbor (ANN)",
        "box-decomposition (BD)",
        "hierarchical navigable small-world (HNSW)",
        "nearest-neighbor descent (NN-descent)",
        "k-nearest-neighbor (kNN)",
        "application programming interface (API)",
        "Open Researcher and Contributor ID (ORCID)",
        "navigating spreading-out graph (NSG)",
        "principal component analysis (PCA)",
        "Windows Subsystem for Linux 2 (WSL2)",
        "application binary interface (ABI)",
        "software development kit (SDK)",
        "Flow Cytometry Standard (FCS)",
        "ImageNet Large Scale Visual Recognition Challenge (ILSVRC)",
        "Knowledge Discovery by Accuracy Maximization (KODAMA)",
        "leave-one-dataset-out (LOODO)",
        "quality assurance (QA)",
        "interquartile range (IQR)",
        "University of Cape Town (UCT)",
        "Technology Services (ICTS)",
    ),
    "faissR_jss_supplement.tex": (
        "central processing unit (CPU)",
        "graphics processing unit (GPU)",
        "Facebook Artificial Intelligence Similarity Search (FAISS)",
        "Compute Unified Device Architecture (CUDA)",
        "approximate nearest-neighbor (ANN)",
        "hierarchical navigable small-world (HNSW)",
        "inverted file (IVF)",
        "product quantization (PQ)",
        "navigating spreading-out graph (NSG)",
        "k-nearest-neighbor (kNN)",
        "nearest-neighbor descent (NN-descent)",
        "application programming interface (API)",
        "application binary interface (ABI)",
        "interprocess communication (IPC)",
        "principal component analysis (PCA)",
        "leave-one-dataset-out (LOODO)",
        "interquartile range (IQR)",
        "Basic Linear Algebra Subprograms (BLAS)",
        "Linear Algebra Package (LAPACK)",
        "University of Cape Town (UCT)",
        "mebibytes (MiB)",
        "Secure Hash Algorithm (SHA-256)",
        "Windows Subsystem for Linux 2 (WSL2)",
        "Flow Cytometry Standard (FCS)",
        "ImageNet Large Scale Visual Recognition Challenge (ILSVRC)",
        "digital object identifier (DOI)",
        "comma-separated values (CSV)",
        "uniform resource locator (URL)",
        "Open Multi-Processing (OpenMP)",
        "Math Kernel Library (MKL)",
        "software development kit (SDK)",
        "HyperText Markup Language (HTML)",
    ),
}
for name, phrases in acronym_requirements.items():
    normalized = re.sub(r"\s+", " ", (HERE / name).read_text())
    normalized = normalized.replace("$k$-nearest-neighbor", "k-nearest-neighbor")
    for phrase in phrases:
        match = re.search(r"\(([^()]+)\)$", phrase)
        abbreviation = match.group(1) if match else None
        first = re.search(
            rf"(?<![A-Za-z0-9]){re.escape(abbreviation)}(?![A-Za-z0-9])",
            normalized,
        ) if abbreviation else None
        if not first:
            continue
        if phrase not in normalized:
            errors.append(f"{name}: missing acronym definition {phrase}")
            continue
        # FAISS/cuVS are official project names in titles; HTML first appears
        # as a LaTeX color-model identifier. Their prose definitions are still
        # required above, but title/source syntax is excluded from ordering.
        if abbreviation and abbreviation not in {"FAISS", "HTML"}:
            first = re.search(
                rf"(?<![A-Za-z0-9]){re.escape(abbreviation)}(?![A-Za-z0-9])",
                normalized,
            )
            if first and normalized.find(phrase) > first.start():
                errors.append(
                    f"{name}: {abbreviation} appears before its definition"
                )
if not re.search(r"not a\s+comparison with a reusable exact\s+index", main):
    errors.append("faissR_jss.tex: rebuilt-Flat scope is not explicit")
if "label{tab:paired-time}" in main:
    errors.append("faissR_jss.tex: secondary CUDA selector table remains in main text")
if "label{tab:supp-cuda-paired}" not in supplement:
    errors.append("faissR_jss_supplement.tex: missing moved CUDA selector table")
if supplement.count("includegraphics[width=0.94\\textwidth]{fig_comprehensive_r_log_ratio.pdf}") != 1:
    errors.append("faissR_jss_supplement.tex: comprehensive figure is missing or duplicated")
evidence_rows = (
    "CPU route-contract cells",
    "CUDA route-contract cells",
    "Public-metric reference records",
    "Completed calibration operating points",
    "Approximate calibration targets met",
    "CUDA automatic independent-query cells",
    "CPU HNSW independent-query cells",
    "CUDA LOODO operating-point cells",
    "CUDA LOODO method-family agreement",
    "CPU LOODO operating-point cells",
    "CPU LOODO method-family agreement",
    "CPU LOODO abstentions",
    "Controlled CPU HNSW route pairs",
    "Successful controlled CPU HNSW pairs",
    "Independently tuned HNSW route runs",
    "Independently tuned HNSW target-matched provider pairs",
    "CPU query-workload cells",
    "CUDA query-workload cells",
    "Comprehensive CPU comparison tasks",
    "Comprehensive CPU paired repetitions",
    "Comprehensive mean-recall-matched pairs",
)
for row in evidence_rows:
    if supplement.count(row) != 1:
        errors.append(
            "faissR_jss_supplement.tex: evidence row is missing or duplicated: "
            f"{row}"
        )
code_html = (HERE / "code.html").read_text()
if not re.search(r"table_11_evidence_audit[.]csv\s+21", code_html):
    errors.append("code.html: stale evidence-table row count")
if errors:
    raise SystemExit("\n".join(errors))
print(f"SUBMISSION SOURCE AUDIT PASSED: faissR {version}")
