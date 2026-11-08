#!/usr/bin/env python3
"""Faithful Aztec repair using the proven geometry pipeline, not a new map layout."""
import json
from pathlib import Path
import subprocess
from polish_dust2 import polish
BASE = 'babfb0ad6e4f47b33f5a1703c7b77f15be1b354a'
PATH = 'assets/maps/de_aztec.glb'

def repair(source):
    return polish(source, cell_size=32.0, source_commit=BASE, generator='Aztec faithful polish v1')

if __name__ == '__main__':
    source = subprocess.check_output(['git','show',BASE+':'+PATH])
    output, report = repair(source)
    Path(PATH).write_bytes(output)
    Path('data/aztec_polish_report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
