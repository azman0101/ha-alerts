#!/usr/bin/env python3
"""Require nonempty Rust and JNA libraries for every expected APK ABI."""

import argparse
import sys
import zipfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", help="Path to the APK to inspect")
    parser.add_argument("--library", required=True, help="Rust library filename, e.g. libapp_core.so")
    parser.add_argument("--abis", nargs="+", default=["arm64-v8a", "x86_64"])
    args = parser.parse_args()

    try:
        with zipfile.ZipFile(args.apk) as apk:
            for abi in args.abis:
                for library in (args.library, "libjnidispatch.so"):
                    name = f"lib/{abi}/{library}"
                    try:
                        entry = apk.getinfo(name)
                    except KeyError:
                        print(f"Missing native library: {name}", file=sys.stderr)
                        return 1
                    if entry.file_size == 0:
                        print(f"Empty native library: {name}", file=sys.stderr)
                        return 1
                    print(f"OK: {name}")
    except (OSError, zipfile.BadZipFile) as error:
        print(f"Cannot inspect APK {args.apk}: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
