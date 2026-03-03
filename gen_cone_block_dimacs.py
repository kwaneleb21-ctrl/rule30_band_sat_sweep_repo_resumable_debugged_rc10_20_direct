#!/usr/bin/env python3
"""
Generate DIMACS CNF for cone-block band periodicity test (exact)
===============================================================

Encodes existence of a time-periodic (period m=lcm(p,2)) band solution for Rule 30 on
i in [-m..m] with existential boundary bits at i=-m-1 and i=m+1 each step.

Constraints at each phase t mod m:
- center X(0,t) = w[t mod p]
- diagonal X(-t+3,t) = (t - diag_phase) mod 2  (alternating 01)
- right edge (optional) X(t,t)=1

Rule 30 dynamics:
X(i,t+1) = X(i-1,t) xor (X(i,t) or X(i+1,t))

All variables are boolean; output is DIMACS CNF.
Use any SAT solver (e.g., kissat, cadical) to decide satisfiable.

Usage:
  python3 gen_cone_block_dimacs.py --p 7 --w 0101010 --right_edge --out p7_w0101010.cnf
  python3 gen_cone_block_dimacs.py --p 7 --w 0101010 --right_edge | kissat

Exit codes:
  0: wrote CNF
"""

from __future__ import annotations
import argparse, math, itertools, sys
from typing import List, Tuple

def rule30_out(l,c,r): 
    return l ^ (c | r)

def build_cnf(p:int, w:str, diag_phase:int, right_edge:bool):
    m = math.lcm(p,2)
    W = 2*m + 1  # sites i in [-m..m] mapped to j=0..W-1 where i=j-m
    # variable ids:
    # X[t][j] for t=0..m-1, j=0..W-1
    def xvar(t,j): 
        return 1 + t*W + j
    base = 1 + m*W
    def bLvar(t): return base + 2*t
    def bRvar(t): return base + 2*t + 1
    nvars = base + 2*m - 1

    cnf: List[List[int]] = []
    def add_unit(v, val):
        cnf.append([v if val else -v])

    # phase constraints
    for t in range(m):
        # center i=0 -> j=m
        add_unit(xvar(t, m), w[t%p]=='1')
        # diagonal i=-t+3 -> j = (-t+3)+m
        i_diag = -t + 3
        if -m <= i_diag <= m:
            j = i_diag + m
            val = ((t - diag_phase) & 1)==1
            add_unit(xvar(t,j), val)
        if right_edge:
            i_edge = t
            if -m <= i_edge <= m:
                add_unit(xvar(t, i_edge + m), True)

    # Rule constraints: for each time t and site j, link to next time tn=(t+1)%m
    for t in range(m):
        tn = (t+1) % m
        for j in range(W):
            l = bLvar(t) if j==0 else xvar(t, j-1)
            c = xvar(t, j)
            r = bRvar(t) if j==W-1 else xvar(t, j+1)
            o = xvar(tn, j)
            # forbid inconsistent assignments: (l,c,r) -> o != f
            for lv,cv,rv in itertools.product([0,1],[0,1],[0,1]):
                f = rule30_out(lv,cv,rv)
                ov = 1 - f
                clause = []
                clause.append(l if lv==0 else -l)
                clause.append(c if cv==0 else -c)
                clause.append(r if rv==0 else -r)
                clause.append(o if ov==0 else -o)
                cnf.append(clause)

    return cnf, nvars, m, W

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--p", type=int, required=True)
    ap.add_argument("--w", type=str, required=True)
    ap.add_argument("--diag_phase", type=int, default=0)
    ap.add_argument("--right_edge", action="store_true")
    ap.add_argument("--out", type=str, default=None)
    args=ap.parse_args()
    if len(args.w)!=args.p or any(ch not in "01" for ch in args.w):
        raise SystemExit("w must be binary length p")

    cnf,nvars,m,W = build_cnf(args.p,args.w,args.diag_phase,args.right_edge)
    nclauses=len(cnf)

    lines=[]
    lines.append(f"c p={args.p} m={m} W={W} diag_phase={args.diag_phase} right_edge={args.right_edge}")
    lines.append(f"p cnf {nvars} {nclauses}")
    for cl in cnf:
        lines.append(" ".join(map(str,cl)) + " 0")
    text="\n".join(lines) + "\n"

    if args.out:
        with open(args.out,"w",encoding="utf-8") as f:
            f.write(text)
    else:
        sys.stdout.write(text)

if __name__=="__main__":
    main()
