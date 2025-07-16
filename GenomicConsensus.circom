pragma circom 2.2.2;

include "node_modules/circomlib/circuits/gates.circom";
include "node_modules/circomlib/circuits/comparators.circom";

// T1: DP cell for pairwise alignment
template T1() {
    signal input e;
    signal input r;
    signal input c;
    signal output es;
    signal output ese;
    signal output ee;
    component eq = IsEqual();
    eq.in[0] <== c;
    eq.in[1] <== r;
    signal c0 <== IsZero()(c);
    signal r0 <== IsZero()(r);
    signal t1 <== eq.out * (1 - r0);
    signal t2 <== c0 * (1 - r0);
    es   <== e * r0;
    ese  <== e * t1;
    ee   <== e * t2;
}

// T2: termination cell
template T2() {
    signal input e;
    signal input c;
    signal output ee;
    signal c0 <== IsZero()(c);
    ee <== e * c0;
}

// pair_aln_seq: returns 1 iff seq aligns to aln (global DP)
template pair_aln_seq(n, m) {
    signal input seq[n];
    signal input aln[m];
    m = m + 1;
    signal output out;
    component a[n][m];
    // first column
    a[0][0] = T1();
    a[0][0].e <== 1;
    a[0][0].r <== seq[0];
    a[0][0].c <== aln[0];
    for (var i = 1; i < n; i++) {
        a[i][0] = T1();
        a[i][0].e <== 0;
        a[i][0].r <== seq[i];
        a[i][0].c <== aln[0];
    }
    // fill rest
    for (var i = 0; i < n; i++) {
        for (var j = 1; j < m; j++) {
            a[i][j] = T1();
            a[i][j].e <== a[i][j-1].ee + (i==0?0:a[i-1][j-1].ese) + (i==0?0:a[i-1][j].es);
            a[i][j].r <== seq[i];
            a[i][j].c <== j == (m-1) ? 0 : aln[j];
        }
    }
    component b[m];
    for (var i = 0; i < m; i++) {
        b[i] = T2();
        b[i].e <== i == 0 ? 0 : b[i-1].ee + a[n-1][i].es + a[n-1][i-1].ese;
        b[i].c <== i == (m-1) ? 0 : aln[i];
    }
    out <== b[m-1].ee;
}

// check_aln_seq: ensure all reads align
template check_aln_seq(nseq, seq_len, aln_len) {
    signal input seq[nseq][seq_len];
    signal input aln[nseq][aln_len];
    signal output y;
    signal t[nseq];
    signal b[nseq];
    for (var i = 0; i < nseq; i++) {
        t[i] <== pair_aln_seq(seq_len, aln_len)(seq[i], aln[i]);
    }
    b[0] <== t[0];
    for (var i = 1; i < nseq; i++) {
        b[i] <== b[i-1] * t[i];
    }
    y <== b[nseq - 1];
}

// CountMatches: sums a list of bits
template CountMatches(nReads) {
    signal input matches[nReads];
    signal output total;
    var sum = 0;
    for (var i = 0; i < nReads; i++) sum += matches[i];
    total <== sum;
}

// MajorityCheck: enforces count > threshold
template MajorityCheck(threshold) {
    signal input count;
    signal output ok;
    component lt = LessThan(32);
    lt.in[0] <== threshold;
    lt.in[1] <== count;
    ok <== lt.out;
    lt.out === 1;
}

// Consensus: aligns reads and votes per column
template Consensus(nReads, seqLen, alnLen, threshold) {
    // Public raw reads and private gapped alignments
    signal input reads[nReads][seqLen];
    signal input alnReads[nReads][alnLen];

    // 1) enforce each read-alignment pair is valid
    component chk = check_aln_seq(nReads, seqLen, alnLen);
    for (var r = 0; r < nReads; r++) {
        for (var i = 0; i < seqLen; i++) {
            chk.seq[r][i] <== reads[r][i];
        }
        for (var j = 0; j < alnLen; j++) {
            chk.aln[r][j] <== alnReads[r][j];
        }
    }
    chk.y === 1;

    // 2) per-column base matching (bases 1..4, 0=gap)
    signal matches[nReads][alnLen][4];
    component eqB[nReads][alnLen][4];
    for (var r = 0; r < nReads; r++) {
        for (var i = 0; i < alnLen; i++) {
            for (var b = 1; b <= 4; b++) {
                eqB[r][i][b-1] = IsEqual();
                eqB[r][i][b-1].in[0] <== alnReads[r][i];
                eqB[r][i][b-1].in[1] <== b;
                matches[r][i][b-1] <== eqB[r][i][b-1].out;
            }
        }
    }

    // 3) count + majority check per base per column
    component cm[alnLen][4];
    component mc[alnLen][4];
    signal countBase[4][alnLen];
    for (var i = 0; i < alnLen; i++) {
        for (var b = 0; b < 4; b++) {
            cm[i][b] = CountMatches(nReads);
            for (var r = 0; r < nReads; r++) {
                cm[i][b].matches[r] <== matches[r][i][b];
            }
            countBase[b][i] <== cm[i][b].total;
            mc[i][b] = MajorityCheck(threshold);
            mc[i][b].count <== countBase[b][i];
            mc[i][b].ok === 1;
        }
    }

    // 4) assemble consensus: pick exactly one base per column
    signal output consensus[alnLen];
    for (var i = 0; i < alnLen; i++) {
        var sumOk = 0;
        for (var b = 0; b < 4; b++) sumOk += mc[i][b].ok;
        sumOk === 1;                       // exactly one winner
        var acc = 0;
        for (var b = 0; b < 4; b++) acc += b * mc[i][b].ok;
        consensus[i] <== acc;
    }

    // 5) overall validity output
    signal output valid;
    valid <== chk.y;
}

// Example instantiation: 10 reads of length 10, alignment length 100, majority threshold = 5
component main { public [reads] } = Consensus(10, 10, 100, 5);
