# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "apache-ossie-dbt @ git+https://github.com/apache/ossie.git@938a439f0170abfe702952f6871f2221690becb5#subdirectory=converters/dbt",
# ]
# ///
"""
Export a dbt v2 (Fusion) semantic layer to an Apache Ossie document.

dbt v2 has no native Ossie support yet, so this script fills the gap using the
official Apache Ossie dbt converter:

  target/semantic_manifest.json  ->  target/ossie_document.yaml

Run from the project root with uv (no install step needed):

  dbt parse && uv run scripts/ossie_bridge.py

The semantic layer itself is authored in the latest dbt YAML spec; there is no
Ossie → dbt direction.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from metricflow_semantics.model.dbt_manifest_parser import parse_manifest_from_dbt_generated_manifest
from ossie_dbt import MSIToOssieConverter


def export_manifest(manifest_path: Path, output: Path, model_name: str) -> None:
    manifest = parse_manifest_from_dbt_generated_manifest(manifest_path.read_text())
    result = MSIToOssieConverter().convert(manifest, ossie_model_name=model_name)
    for issue in result.issues:
        print(f"[warning] {issue.issue_type.value}: {issue.element_name}", file=sys.stderr)
    output.write_text(result.output.to_ossie_yaml())
    print(f"{manifest_path} -> {output}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("-i", "--input", type=Path, default=Path("target/semantic_manifest.json"))
    parser.add_argument("-o", "--output", type=Path, default=Path("target/ossie_document.yaml"))
    parser.add_argument("--model-name", default="ztc_analytics")
    args = parser.parse_args()
    export_manifest(args.input, args.output, args.model_name)


if __name__ == "__main__":
    main()
