#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Rule 30 cone-block band SAT sweep (Kissat) — resumable
# ============================================================
# New features:
#   - Resume: skips (p,w) pairs already present in results.csv
#   - Chunking: optional WORD_START/WORD_END to sweep a subset
#   - Robust status parsing + per-instance CNF/log paths stored
#
# Requirements:
#   python3, kissat, sha256sum
# Optional:
#   timeout (GNU coreutils) if TIMEOUT_SECS is set
# ============================================================

GEN_PY="${GEN_PY:-./gen_cone_block_dimacs.py}"
OUTDIR="${OUTDIR:-sat_sweep_outputs}"
P_START="${P_START:-13}"
P_END="${P_END:-20}"
DIAG_PHASE="${DIAG_PHASE:-0}"
RIGHT_EDGE_FLAG="${RIGHT_EDGE_FLAG:---right_edge}"   # set empty to disable
KISSAT_BIN="${KISSAT_BIN:-kissat}"
KISSAT_OPTS="${KISSAT_OPTS:-}"
TIMEOUT_SECS="${TIMEOUT_SECS:-}"                     # e.g. 20

# Optional word-range chunking (integers). If set, only words in [WORD_START, WORD_END] are processed per p.
# WORD_END is inclusive. Use empty to disable.
WORD_START="${WORD_START:-}"
WORD_END="${WORD_END:-}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 not found." >&2
  exit 1
fi
if ! command -v "${KISSAT_BIN}" >/dev/null 2>&1; then
  echo "ERROR: kissat not found in PATH. Install kissat or set KISSAT_BIN." >&2
  exit 1
fi
if ! command -v sha256sum >/dev/null 2>&1; then
  echo "ERROR: sha256sum not found." >&2
  exit 1
fi
if [[ ! -f "${GEN_PY}" ]]; then
  echo "ERROR: CNF generator not found at: ${GEN_PY}" >&2
  exit 1
fi

mkdir -p "${OUTDIR}/cnf" "${OUTDIR}/logs"
CSV="${OUTDIR}/results.csv"
META="${OUTDIR}/meta.txt"
DONESET="${OUTDIR}/done.set"

# Build done-set from CSV if present; store keys "p,w"
if [[ -f "${CSV}" ]]; then
  tail -n +2 "${CSV}" | awk -F',' '{print $1","$2}' | sort -u > "${DONESET}" || true
else
  echo "p,w,diag_phase,right_edge,cnf_path,cnf_sha256,solver,solver_opts,status,solver_seconds,solver_log" > "${CSV}"
  : > "${DONESET}"
fi

{
  echo "SAT sweep meta"
  echo "date_utc=$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  echo "gen_py=${GEN_PY}"
  echo "kissat_bin=${KISSAT_BIN}"
  echo "kissat_opts=${KISSAT_OPTS}"
  echo "p_start=${P_START}"
  echo "p_end=${P_END}"
  echo "diag_phase=${DIAG_PHASE}"
  echo "right_edge_flag=${RIGHT_EDGE_FLAG}"
  echo "timeout_secs=${TIMEOUT_SECS}"
  echo "word_start=${WORD_START}"
  echo "word_end=${WORD_END}"
  echo "kissat_version=$(${KISSAT_BIN} --version 2>/dev/null || true)"
} > "${META}"

gen_words() {
  local p="$1"
  python3 - <<PY
p = int("${p}")
start = ${WORD_START if WORD_START else 0}
end = ${WORD_END if WORD_END else (1<<p)-1}
if start < 0: start = 0
if end > (1<<p)-1: end = (1<<p)-1
for b in range(start, end+1):
    print(format(b, "0{}b".format(p)))
PY
}

already_done() {
  local p="$1"
  local w="$2"
  grep -qx "${p},${w}" "${DONESET}"
}

mark_done() {
  local p="$1"
  local w="$2"
  echo "${p},${w}" >> "${DONESET}"
}

run_one() {
  local p="$1"
  local w="$2"
  local tag="p${p}_w${w}_dp${DIAG_PHASE}"
  local cnf="${OUTDIR}/cnf/${tag}.cnf"
  local log="${OUTDIR}/logs/${tag}.log"

  python3 "${GEN_PY}" --p "${p}" --w "${w}" --diag_phase "${DIAG_PHASE}" ${RIGHT_EDGE_FLAG} --out "${cnf}"
  local cnf_hash
  cnf_hash="$(sha256sum "${cnf}" | awk '{print $1}')"

  local right_edge_bool="false"
  if [[ -n "${RIGHT_EDGE_FLAG}" ]]; then right_edge_bool="true"; fi

  local t0 t1 elapsed status
  t0="$(python3 - <<'PY'
import time; print(time.time())
PY
)"

  if [[ -n "${TIMEOUT_SECS}" ]] && command -v timeout >/dev/null 2>&1; then
    if timeout "${TIMEOUT_SECS}" "${KISSAT_BIN}" ${KISSAT_OPTS} "${cnf}" > "${log}" 2>&1; then
      true
    else
      rc=$?
      if [[ $rc -eq 124 ]]; then
        echo "${p},${w},${DIAG_PHASE},${right_edge_bool},${cnf},${cnf_hash},kissat,${KISSAT_OPTS},TIMEOUT,${TIMEOUT_SECS},${log}" >> "${CSV}"
        mark_done "${p}" "${w}"
        return 0
      elif [[ $rc -eq 10 || $rc -eq 20 ]]; then
        # kissat uses 10=SAT, 20=UNSAT; record immediately (skip grep parsing)
        if [[ $rc -eq 10 ]]; then status="SAT"; else status="UNSAT"; fi
        t1="$(python3 - <<'PY'
import time; print(time.time())
PY
)"
        elapsed="$(python3 - <<PY
t0=float("${t0}"); t1=float("${t1}")
print("{:.6f}".format(t1-t0))
PY
)"
        echo "${p},${w},${DIAG_PHASE},${right_edge_bool},${cnf},${cnf_hash},kissat,${KISSAT_OPTS},${status},${elapsed},${log}" >> "${CSV}"
        mark_done "${p}" "${w}"
        return 0
      else
        echo "${p},${w},${DIAG_PHASE},${right_edge_bool},${cnf},${cnf_hash},kissat,${KISSAT_OPTS},ERROR_RC_${rc},,${log}" >> "${CSV}"
        mark_done "${p}" "${w}"
        return 0
      fi
    fi
  else
    "${KISSAT_BIN}" ${KISSAT_OPTS} "${cnf}" > "${log}" 2>&1 || true
  fi

  t1="$(python3 - <<'PY'
import time; print(time.time())
PY
)"
  elapsed="$(python3 - <<PY
t0=float("${t0}"); t1=float("${t1}")
print("{:.6f}".format(t1-t0))
PY
)"

  if grep -qi "s[[:space:]]\\+SATISFIABLE" "${log}"; then
    status="SAT"
  elif grep -qi "s[[:space:]]\\+UNSATISFIABLE" "${log}"; then
    status="UNSAT"
  else
    status="UNKNOWN"
  fi

  echo "${p},${w},${DIAG_PHASE},${right_edge_bool},${cnf},${cnf_hash},kissat,${KISSAT_OPTS},${status},${elapsed},${log}" >> "${CSV}"
  mark_done "${p}" "${w}"
}

echo "Resumable sweep: p=${P_START}..${P_END} diag_phase=${DIAG_PHASE} right_edge=${RIGHT_EDGE_FLAG:-none}"
if [[ -n "${WORD_START}" || -n "${WORD_END}" ]]; then
  echo "Word chunk: [${WORD_START:-0} .. ${WORD_END:-max}]"
fi
echo "CSV: ${CSV}"
echo "DONESET: ${DONESET}"
echo

# ensure doneset sorted unique occasionally (cheap)
sort -u "${DONESET}" -o "${DONESET}" || true

for ((p=P_START; p<=P_END; p++)); do
  echo "=== p=${p} ==="
  total=$((1<<p))
  count=0
  skipped=0

  while IFS= read -r w; do
    count=$((count+1))
    if already_done "${p}" "${w}"; then
      skipped=$((skipped+1))
      continue
    fi
    if (( count % 128 == 0 )); then
      echo "  progress: ${count}/${total} (skipped so far: ${skipped})"
    fi
    run_one "${p}" "${w}"
  done < <(gen_words "${p}")

  echo "=== done p=${p} (skipped ${skipped}) ==="
  echo
done

echo "All done."
echo "CSV: ${CSV}"
echo "Logs: ${OUTDIR}/logs/"
echo "CNFs: ${OUTDIR}/cnf/"
