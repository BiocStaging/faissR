#!/usr/bin/env python3

import argparse
import csv
import os
import re
from collections import defaultdict
from pathlib import Path


CURRENT_METRICS = {"euclidean", "cosine", "correlation"}
PUBLICATION_METHODS = {
    "cpu": {"faissR_cpu_auto", "faissR_cpu_hnsw", "faissR_cpu_ivf"},
    "cuda": {"faissR_cuda_gpu_resident_auto", "faissR_cuda_cagra", "faissR_cuda_ivf"},
}
DATASET_GROUPS = (
    ("COIL20", "USPS", "FashionMNIST", "flow18", "MNIST", "MetRef"),
    ("FlowRepository_FR-FCM-ZYRM_files",),
    ("imagenet",),
    ("mass41",),
)


def exported(text, name):
    match = re.search(rf"^export {re.escape(name)}='([^']*)'", text, re.MULTILINE)
    return match.group(1) if match else ""


def semantic_key(name):
    return re.sub(r"^[0-9]+_", "", name)


def read_first(path):
    with path.open(newline="", encoding="utf-8") as handle:
        return next(csv.DictReader(handle))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--suite-root", required=True)
    parser.add_argument("--results-root", required=True)
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--scope", choices=("publication", "all"), default="publication")
    parser.add_argument("--group-datasets", action="store_true")
    args = parser.parse_args()

    suite_root = Path(args.suite_root).resolve()
    results_root = Path(args.results_root).resolve()
    out_dir = Path(args.out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    sources = defaultdict(list)
    observed = defaultdict(set)
    for config_path in results_root.glob("**/jmlr_benchmark_config.csv"):
        config = read_first(config_path)
        worker_dir = config_path.parent / "worker_results"
        if not worker_dir.is_dir():
            continue
        for method in filter(None, config.get("methods", "").split(",")):
            for metric in filter(None, config.get("metrics", "").split(",")):
                if metric not in CURRENT_METRICS:
                    continue
                key = (config.get("backend", ""), method, metric)
                sources[key].append(str(config_path.parent))
                for result in worker_dir.glob("*.csv"):
                    observed[key].add(semantic_key(result.name))

    tasks = {"cpu": [], "cuda": []}
    summary = []
    launchers = sorted((suite_root / "final_campaign" / "held_out").glob("**/*.sh"))
    for launcher in launchers:
        text = launcher.read_text(encoding="utf-8")
        backend = exported(text, "BACKEND")
        method = exported(text, "METHOD_ID")
        metrics = exported(text, "METHOD_METRICS").split(",")
        datasets = exported(text, "DATASETS").split(",")
        include_external = exported(text, "INCLUDE_EXTERNAL") == "TRUE"
        if backend not in tasks or not method:
            continue
        if args.scope == "publication" and method not in PUBLICATION_METHODS[backend]:
            continue
        expected_per_dataset = 24 if include_external else 72
        for metric in metrics:
            if metric not in CURRENT_METRICS:
                continue
            key = (backend, method, metric)
            metric_rows = []
            for dataset in filter(None, datasets):
                marker = f"{dataset}__{method}__{metric}__"
                completed = sum(marker in item for item in observed[key])
                missing = max(0, expected_per_dataset - completed)
                summary.append({
                    "backend": backend,
                    "method": method,
                    "metric": metric,
                    "dataset": dataset,
                    "expected": expected_per_dataset,
                    "completed": completed,
                    "missing": missing,
                    "launcher": str(launcher),
                })
                metric_rows.append((dataset, missing))
            groups = DATASET_GROUPS if args.group_datasets else tuple((x,) for x, _ in metric_rows)
            missing_by_dataset = dict(metric_rows)
            for group in groups:
                selected = [dataset for dataset in group if dataset in missing_by_dataset]
                missing = sum(missing_by_dataset[dataset] for dataset in selected)
                if not missing:
                    continue
                tasks[backend].append({
                    "launcher": str(launcher),
                    "dataset": ",".join(selected),
                    "resume_results_dirs": os.pathsep.join(sorted(set(sources[key]))),
                    "missing_before_resume": missing,
                })

    with (out_dir / "held_out_completion.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(summary[0]))
        writer.writeheader()
        writer.writerows(summary)

    for backend, backend_tasks in tasks.items():
        path = out_dir / f"held_out_resume_{backend}.tsv"
        with path.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(
                handle,
                fieldnames=["launcher", "dataset", "resume_results_dirs", "missing_before_resume"],
                delimiter="\t",
            )
            writer.writeheader()
            writer.writerows(backend_tasks)
        print(f"{backend}: {len(backend_tasks)} incomplete dataset shards -> {path}")


if __name__ == "__main__":
    main()
