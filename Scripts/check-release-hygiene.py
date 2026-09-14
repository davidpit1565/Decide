#!/usr/bin/env python3
"""Fails if anything test-only could reach a shipping build.

Run in CI and before an archive. Three checks:

  1. The UI test harness file is entirely inside `#if DEBUG`.
  2. Every reference to it from other app code sits inside a `#if DEBUG` block.
  3. No credential-shaped literal is committed in the app or its configuration.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
HARNESS = ROOT / "App/Services/UITestHarness.swift"
failures = []


def check_harness_is_debug_only() -> None:
    lines = [line.rstrip("\n") for line in HARNESS.read_text().splitlines() if line.strip()]
    if not lines or lines[0].strip() != "#if DEBUG":
        failures.append(f"{HARNESS.relative_to(ROOT)} must begin with '#if DEBUG'")
    if not lines or lines[-1].strip() != "#endif":
        failures.append(f"{HARNESS.relative_to(ROOT)} must end with '#endif'")


def check_references_are_guarded() -> None:
    for path in (ROOT / "App").rglob("*.swift"):
        if path == HARNESS:
            continue
        depth = 0
        debug_depth = None
        for number, line in enumerate(path.read_text().splitlines(), start=1):
            stripped = line.strip()
            if stripped.startswith("#if"):
                depth += 1
                if debug_depth is None and "DEBUG" in stripped:
                    debug_depth = depth
            elif stripped.startswith("#endif"):
                if debug_depth == depth:
                    debug_depth = None
                depth = max(0, depth - 1)
            elif "UITestHarness" in stripped and not stripped.startswith("//"):
                if debug_depth is None:
                    failures.append(
                        f"{path.relative_to(ROOT)}:{number} references UITestHarness outside #if DEBUG"
                    )


SECRET_PATTERNS = [
    (re.compile(r"sk-ant-[A-Za-z0-9_\-]{8,}"), "an Anthropic API key"),
    (re.compile(r"\bsk-[A-Za-z0-9]{32,}"), "an API key"),
    (re.compile(r"(?i)\b(api[_-]?key|secret|bearer[_-]?token)\s*[:=]\s*[\"'][^\"'$()\s]{12,}[\"']"), "a hard-coded credential"),
]

ALLOWED = {"Scripts/check-release-hygiene.py"}


def check_no_secrets() -> None:
    for folder, patterns in (("App", "*.swift"), ("Config", "*"), ("Packages", "*.swift")):
        for path in (ROOT / folder).rglob(patterns):
            if not path.is_file() or path.suffix in {".png", ".xcassets"}:
                continue
            relative = str(path.relative_to(ROOT))
            if relative in ALLOWED:
                continue
            try:
                text = path.read_text()
            except (UnicodeDecodeError, OSError):
                continue
            for pattern, description in SECRET_PATTERNS:
                for match in pattern.finditer(text):
                    failures.append(f"{relative}: looks like {description}: {match.group(0)[:24]}…")


check_harness_is_debug_only()
check_references_are_guarded()
check_no_secrets()

if failures:
    print("Release hygiene check failed:\n")
    for failure in failures:
        print(f"  - {failure}")
    sys.exit(1)

print("Release hygiene check passed: no test-only code and no credentials can reach a shipping build.")
