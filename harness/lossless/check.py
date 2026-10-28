#!/usr/bin/env python3
"""Verify the generated-fixture local decode/seek baseline; report streaming observations separately."""
import json
import math
from pathlib import Path
import sys

rows = [json.loads(line.removeprefix("LOSSLESS ")) for line in Path(sys.argv[1]).read_text().splitlines()
        if line.startswith("LOSSLESS ")]
if not rows or rows[-1].get("test") != "complete":
    raise SystemExit("FAIL: probe did not complete")
rates = {"cd.flac": 44100, "hires.flac": 96000, "alac.m4a": 48000, "alac-fast.m4a": 48000}
checks = 0
for name, rate in rates.items():
    local = [r for r in rows if r.get("file") == name and r["test"] == "local-decode-seek"]
    assert len(local) == 2, (name, "missing local decode")
    assert {r["clientRate"] for r in local} == {rate, 44100}, (name, "wrong rates")
    for row in local:
        assert row["status"] == row["seekStatus"] == 0, row
        assert row["sourceRate"] == rate, row
        assert row["frames"] == 12 * row["clientRate"], row
        assert math.isfinite(row["energy"]) and row["energy"] > 0, row
        assert row["seekFrames"] == 1024, row
        if row["clientRate"] == rate:
            assert math.isfinite(row["seekMaxError"]) and row["seekMaxError"] < 0.00004, row
        checks += 1
    local_reader = [r for r in rows if r.get("file") == name and r["test"] == "asset-reader" and not r["remote"]]
    assert len(local_reader) == 1, (name, "missing reader")
    row = local_reader[0]
    assert row["started"] and row["readerStatus"] == 2, row
    assert abs(row["firstPTS"] - 3.125) <= 1/rate and abs(row["frames"] - rate) <= 1, row
    checks += 1
    for row in rows:
        if row.get("file") != name:
            continue
        if row["test"] == "parsed-packet-decode":
            print(f"OBSERVATION {name}: packet decode status={row['status']}, "
                  f"frames={row['frames']}/{12*rate}, max error={row['maxError']:.3g}")
        elif row["test"] == "incremental-parser":
            print(f"OBSERVATION {name}: parser status={row['status']}, ready={row['ready']}")
        elif row["test"] == "asset-reader" and row["remote"]:
            print(f"OBSERVATION {name}: remote reader started={row['started']}, error={row['errorCode']}")
print(f"PASS: {checks} local decode/seek cases. Streaming observations are not streaming acceptance tests.")
