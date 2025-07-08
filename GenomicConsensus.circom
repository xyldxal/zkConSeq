pragma circom 2.2.2;

include "node_modules/circomlib/circuits/gates.circom";
include "node_modules/circomlib/circuits/comparators.circom";


// BaseMatch: compares two bases
template BaseMatch() {
    signal input a;
    signal input b;
    signal output match;
    component eq = IsEqual();
    eq.in[0] <== a;
    eq.in[1] <== b;
    match <== eq.out;
}

template CountMatches(nReads) {
    signal input matches[nReads];
    signal output total;
    var sum = 0;
    for (var i = 0; i < nReads; i++) {
        sum += matches[i];
    }
    total <== sum;
}

template MajorityCheck(threshold) {
    signal input count;
    signal output ok;
    component lt = LessThan(32);
    lt.in[0] <== threshold;
    lt.in[1] <== count;
    ok <== lt.out;
    lt.out === 1;
}

// RangeCheck: ensures a < 4
template RangeCheck() {
    signal input a;
    component lt = LessThan(32);
    lt.in[0] <== a;
    lt.in[1] <== 4;
    lt.out === 1;
}



// Consensus: enforces consensus matches majority
template Consensus(nReads, readLen, threshold) {
    // Public inputs
    signal input reads[nReads][readLen];
    // Private consensus sequence
    signal input consensus[readLen];

    // Match signals
    signal matches[nReads][readLen];

    component rangeChk[readLen];
    component baseMatch[nReads][readLen];
    component cm[readLen];
    component mc[readLen];

    for (var i = 0; i < readLen; i++) {
        // valid consensus base
        rangeChk[i] = RangeCheck();
        rangeChk[i].a <== consensus[i];
        // per-read match
        for (var j = 0; j < nReads; j++) {
            baseMatch[j][i] = BaseMatch();
            baseMatch[j][i].a <== reads[j][i];
            baseMatch[j][i].b <== consensus[i];
            matches[j][i] <== baseMatch[j][i].match;
        }
        // count matches
        cm[i] = CountMatches(nReads);
        for (var j = 0; j < nReads; j++) {
            cm[i].matches[j] <== matches[j][i];
        }
        // majority check
        mc[i] = MajorityCheck(threshold);
        mc[i].count <== cm[i].total;
    }

    
    // Validity output
    signal output valid;
    // Always valid if circuit constraints pass
    valid <== 1;
} 

// Main instantiation: 3 reads of length 5, strict majority threshold = 1
component main { public [reads]} = Consensus(100, 100, 50);
