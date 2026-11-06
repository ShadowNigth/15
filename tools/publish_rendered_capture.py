#!/usr/bin/env python3
"""Transport a small rendered JPEG through bounded GitHub check annotations."""
import base64
from pathlib import Path
import sys

name = sys.argv[1]
assert name in {"as_oilrig", "cs_747", "cs_estate"}
image = Path("/tmp/task48-captures") / f"{name}.jpg"
if not image.exists():
    raise SystemExit(f"Missing rendered capture: {image}")
data = base64.b64encode(image.read_bytes()).decode("ascii")
# Check annotation messages are truncated at 4096 characters. A separate
# workflow step per image reserves its ten annotation slots for these chunks.
chunks = [data[i : i + 3500] for i in range(0, len(data), 3500)]
assert len(chunks) <= 10, "JPEG exceeds the bounded diagnostic transport budget"
for i, chunk in enumerate(chunks):
    print(f"::notice title=Task48 JPEG {name} {i + 1}/{len(chunks)}::{chunk}")
