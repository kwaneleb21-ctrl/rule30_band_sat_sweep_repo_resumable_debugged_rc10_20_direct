# Rule 30 Band SAT Sweep (Kissat) — Resumable

This repo generates DIMACS CNFs for the cone-block band periodicity test and runs Kissat.
It supports resuming partial runs and chunking the word-range.

## Files
- `gen_cone_block_dimacs.py` — CNF generator
- `run_kissat_sweep.sh` — resumable sweep runner

## Resume behavior
- Results append to `OUTDIR/results.csv`.
- A checkpoint file `OUTDIR/done.set` stores completed pairs `p,w`.
- Re-running the script will skip already-completed instances.

## Chunking
Set `WORD_START` and `WORD_END` (inclusive) to run only a subset of words per p.
Example (first 1024 words for p=20):
```bash
P_START=20 P_END=20 WORD_START=0 WORD_END=1023 ./run_kissat_sweep.sh
```

## Example
```bash
chmod +x run_kissat_sweep.sh
P_START=13 P_END=20 OUTDIR=run_full KISSAT_OPTS="--quiet" ./run_kissat_sweep.sh
```
