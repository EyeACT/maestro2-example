#!/usr/bin/env python3
"""Print all DICOM tags for a given file path."""

from __future__ import annotations

import argparse
import os
import sys
from typing import Iterable

import pydicom
from pydicom.dataset import Dataset
from pydicom.multival import MultiValue
from pydicom.sequence import Sequence


def format_value(value: object, max_len: int = 200) -> str:
    """Return a concise string representation for a DICOM value."""
    if isinstance(value, Sequence):
        return f"Sequence with {len(value)} item(s)"

    if isinstance(value, (bytes, bytearray)):
        return f"<{type(value).__name__}: {len(value)} bytes>"

    if isinstance(value, MultiValue):
        rendered = ", ".join(str(v) for v in value)
    else:
        rendered = str(value)

    if len(rendered) > max_len:
        rendered = f"{rendered[: max_len - 3]}..."

    return rendered


def iter_dataset_lines(ds: Dataset, indent: int = 0) -> Iterable[str]:
    """Yield printable lines for each data element in a dataset."""
    pad = "  " * indent
    for elem in ds:
        tag = f"({elem.tag.group:04X},{elem.tag.element:04X})"
        keyword = elem.keyword or "-"
        name = elem.name or "Unknown"
        vr = elem.VR or "--"
        value_text = format_value(elem.value)
        yield f"{pad}{tag} {keyword:<32} {name:<40} VR={vr:<4} Value={value_text}"

        if elem.VR == "SQ":
            for idx, item in enumerate(elem.value, start=1):
                yield f"{pad}  Item #{idx}"
                yield from iter_dataset_lines(item, indent=indent + 2)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Print all tags from a DICOM file."
    )
    parser.add_argument(
        "dicom_path",
        help="Path to the DICOM file.",
    )
    parser.add_argument(
        "--stop-before-pixels",
        action="store_true",
        help="Skip reading Pixel Data for faster output on large files.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    dicom_path = args.dicom_path

    if not os.path.exists(dicom_path):
        print(f"Error: file not found: {dicom_path}", file=sys.stderr)
        return 1

    if not os.path.isfile(dicom_path):
        print(f"Error: not a file: {dicom_path}", file=sys.stderr)
        return 1

    try:
        ds = pydicom.dcmread(
            dicom_path,
            force=True,
            stop_before_pixels=args.stop_before_pixels,
        )
    except Exception as exc:
        print(f"Error reading DICOM: {exc}", file=sys.stderr)
        return 2

    print(f"DICOM file: {dicom_path}")
    print("=" * 120)
    for line in iter_dataset_lines(ds):
        print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
