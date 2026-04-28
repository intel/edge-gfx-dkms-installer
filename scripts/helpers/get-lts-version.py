#!/usr/bin/env python3
import json
import re
import sys
import urllib.request
from dataclasses import dataclass
import argparse


@dataclass(order=True, frozen=True)
class Version:
	major: int
	minor: int
	patch: int
	raw: str


def parse_version(s: str) -> Version | None:
	m = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)", s.strip())
	if not m:
		return None
	return Version(int(m.group(1)), int(m.group(2)), int(m.group(3)), s.strip())


def main() -> int:
	parser = argparse.ArgumentParser()
	parser.add_argument(
		"--series",
		help="Filter longterm releases to a specific major.minor (e.g. 6.12)",
		default="",
	)
	args = parser.parse_args()

	series = args.series.strip()
	if series and not re.fullmatch(r"\d+\.\d+", series):
		print("", end="")
		return 2

	url = "https://www.kernel.org/releases.json"
	with urllib.request.urlopen(url, timeout=10) as resp:
		data = json.loads(resp.read().decode("utf-8"))

	releases = data.get("releases") or []
	candidates: list[Version] = []
	for r in releases:
		if str(r.get("moniker", "")).lower() != "longterm":
			continue
		v = parse_version(str(r.get("version", "")))
		if v:
			if series and not v.raw.startswith(series + "."):
				continue
			candidates.append(v)

	if not candidates:
		print("", end="")
		return 2

	best = max(candidates)
	print(best.raw)
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
