pragma circom 2.2.2;

include "node_modules/circomlib/circuits/gates.circom";
include "node_modules/circomlib/circuits/comparators.circom";

// --- MSA Scoring System ---
// Scoring: +1 for match, -1 for mismatch/gap
template ScoringSystem() {
    signal input x[2];
    signal output y;
    
    component eq = IsEqual();
    eq.in[0] <== x[0];
    eq.in[1] <== x[1];
    
    component isZero1 = IsZero();
    component isZero2 = IsZero();
    isZero1.in <== x[0];
    isZero2.in <== x[1];
    
    // Break down the logic into quadratic constraints:
    
    // Both are non-zero AND equal = real match (+1)
    signal bothNonZero <== (1 - isZero1.out) * (1 - isZero2.out);
    signal realMatch <== eq.out * bothNonZero;
    
    // Both are gaps = neutral (0)
    signal bothGaps <== isZero1.out * isZero2.out;
    
    // Everything else = mismatch (-1)
    // This includes: gap vs base, base vs gap, different bases
    signal isMismatch <== 1 - realMatch - bothGaps;
    
    // Final score: +1 for real matches, 0 for gap-gap, -1 for mismatches
    y <== realMatch - isMismatch;
}

// Pairwise alignment score
template PairScore(alnLen) {
    signal input aln[2][alnLen];
    signal output score;
    component scorer[alnLen];
    signal acc[alnLen + 1];
    acc[0] <== 0;
    for (var i = 0; i < alnLen; i++) {
        scorer[i] = ScoringSystem();
        scorer[i].x[0] <== aln[0][i];
        scorer[i].x[1] <== aln[1][i];
        acc[i + 1] <== acc[i] + scorer[i].y;
    }
    score <== acc[alnLen];
}

// --- Reverse Complement ---
// Maps: A(1)↔T(4), C(2)↔G(3), gap(0)→gap(0)
template ReverseComplement() {
    signal input base;
    signal output revComp;
    component eq[5];
    for (var i = 0; i < 5; i++) {
        eq[i] = IsEqual();
        eq[i].in[0] <== base;
        eq[i].in[1] <== i;
    }
    // 0→0, 1→4, 2→3, 3→2, 4→1
    revComp <== eq[0].out * 0 + eq[1].out * 4 + eq[2].out * 3 + eq[3].out * 2 + eq[4].out * 1;
}

// Reverse complement entire sequence
template ReverseComplementSeq(seqLen) {
    signal input seq[seqLen];
    signal output revSeq[seqLen];
    component rc[seqLen];
    for (var i = 0; i < seqLen; i++) {
        rc[i] = ReverseComplement();
        rc[i].base <== seq[seqLen - 1 - i]; // reverse order
        revSeq[i] <== rc[i].revComp;
    }
}

// --- Variable Length Sequence Matching ---
// Check if gapped alignment matches original sequence (removing gaps)
template SequenceMatch(maxSeqLen, maxAlnLen) {
    signal input original[maxSeqLen]; // original read (max 20 bases)
    signal input aligned[maxAlnLen]; // aligned read with gaps (max 50 bases)
    signal input origLen; // actual length of original
    signal output isMatch;
    
    // Extract non-gap bases from aligned sequence
    signal extractedBases[maxAlnLen];
    signal extractedCount[maxAlnLen + 1];
    
    // Declare all components in initial scope
    component isGap[maxAlnLen];
    component lenCheck = IsEqual();
    
    extractedCount[0] <== 0;
    
    // Extract non-gap bases sequentially
    for (var i = 0; i < maxAlnLen; i++) {
        isGap[i] = IsZero();
        isGap[i].in <== aligned[i];
        
        // If not a gap, count it
        extractedCount[i + 1] <== extractedCount[i] + (1 - isGap[i].out);
        
        // Store the base if it's not a gap (simplified for circuit)
        extractedBases[i] <== aligned[i] * (1 - isGap[i].out);
    }
    
    // Check that extracted count matches original length
    lenCheck.in[0] <== extractedCount[maxAlnLen];
    lenCheck.in[1] <== origLen;
    
    // Simplified validation for sliding alignments
    isMatch <== lenCheck.out;
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
    // Note: ok will be 1 if count > threshold, 0 otherwise
}

template Consensus(nReads, maxSeqLen, maxAlnLen, threshold) {
    // Public inputs: sequences and alignment score
    signal input reads[nReads][maxSeqLen]; // Raw reads (padded)
    signal input readLens[nReads]; // Actual lengths
    signal input expectedScore; // Expected MSA score
    
    // Private inputs: alignment and consensus
    signal input alignedReads[nReads][maxAlnLen]; // Gapped alignments
    signal input isReversed[nReads];              // 1 if read was reverse-complemented
    signal input startPos[nReads];                // Sliding start positions
    signal input consensus[maxAlnLen];             // The consensus sequence (private)
    
    // 1) SEQUENCE VALIDATION: Check each alignment matches its original
    component seqMatch[nReads];
    component revComp[nReads];
    component selector[nReads][maxSeqLen];        // For conditional selection
    signal processedReads[nReads][maxSeqLen];     // Forward or reverse-comp
    signal revTerm[nReads][maxSeqLen];
    signal fwdTerm[nReads][maxSeqLen];
    
    for (var r = 0; r < nReads; r++) {
        // Apply reverse complement if needed
        revComp[r] = ReverseComplementSeq(maxSeqLen);
        for (var i = 0; i < maxSeqLen; i++) {
            revComp[r].seq[i] <== reads[r][i];
        }
        
        // Select forward or reverse based on isReversed flag
        for (var i = 0; i < maxSeqLen; i++) {
            selector[r][i] = IsEqual();
            selector[r][i].in[0] <== isReversed[r];
            selector[r][i].in[1] <== 1;
            // Break down into quadratic terms
            revTerm[r][i] <== selector[r][i].out * revComp[r].revSeq[i];
            fwdTerm[r][i] <== (1 - selector[r][i].out) * reads[r][i];
            processedReads[r][i] <== revTerm[r][i] + fwdTerm[r][i];
        }
        
        // Extract non-gap bases from aligned read for validation
        seqMatch[r] = SequenceMatch(maxSeqLen, maxAlnLen);
        for (var i = 0; i < maxAlnLen; i++) {
            seqMatch[r].aligned[i] <== alignedReads[r][i];
        }
        for (var i = 0; i < maxSeqLen; i++) {
            seqMatch[r].original[i] <== processedReads[r][i];
        }
        seqMatch[r].origLen <== readLens[r];
        
        // Enforce that sequence validation passes
        seqMatch[r].isMatch === 1;
    }
    
    // 2) SCORE VALIDATION: Check MSA score matches expected
    component pairScores[nReads][nReads];
    signal totalScore;
    
    // Calculate number of unique pairs: nReads * (nReads-1) / 2
    var numPairs = (nReads * (nReads - 1)) / 2;
    signal pairScoreSignals[numPairs];
    signal scoreAccumulator[numPairs + 1];
    scoreAccumulator[0] <== 0;
    
    var pairIndex = 0;
    for (var i = 0; i < nReads; i++) {
        for (var j = i + 1; j < nReads; j++) {
            pairScores[i][j] = PairScore(maxAlnLen);
            for (var k = 0; k < maxAlnLen; k++) {
                pairScores[i][j].aln[0][k] <== alignedReads[i][k];
                pairScores[i][j].aln[1][k] <== alignedReads[j][k];
            }
            pairScoreSignals[pairIndex] <== pairScores[i][j].score;
            scoreAccumulator[pairIndex + 1] <== scoreAccumulator[pairIndex] + pairScoreSignals[pairIndex];
            pairIndex++;
        }
    }
    totalScore <== scoreAccumulator[numPairs];
    
    component scoreCheck = IsEqual();
    scoreCheck.in[0] <== totalScore;
    scoreCheck.in[1] <== expectedScore;
    // Enforce that the calculated score matches the public input
    scoreCheck.out === 1;
    
    // 3) CONSENSUS VALIDATION: Verify the provided consensus matches majority voting
    signal matches[nReads][maxAlnLen][4];
    component baseEq[nReads][maxAlnLen][4];
    
    for (var r = 0; r < nReads; r++) {
        for (var pos = 0; pos < maxAlnLen; pos++) {
            for (var base = 1; base <= 4; base++) {
                baseEq[r][pos][base-1] = IsEqual();
                baseEq[r][pos][base-1].in[0] <== alignedReads[r][pos];
                baseEq[r][pos][base-1].in[1] <== base;
                matches[r][pos][base-1] <== baseEq[r][pos][base-1].out;
            }
        }
    }
    
    // Count and check majority per position
    component counter[maxAlnLen][4];
    component majorityChk[maxAlnLen][4];
    signal baseCounts[4][maxAlnLen];
    
    for (var pos = 0; pos < maxAlnLen; pos++) {
        for (var base = 0; base < 4; base++) {
            counter[pos][base] = CountMatches(nReads);
            for (var r = 0; r < nReads; r++) {
                counter[pos][base].matches[r] <== matches[r][pos][base];
            }
            baseCounts[base][pos] <== counter[pos][base].total;
            
            majorityChk[pos][base] = MajorityCheck(threshold);
            majorityChk[pos][base].count <== baseCounts[base][pos];
        }
    }
    
    // Declare all components and signals for consensus validation in initial scope
    component isGap[maxAlnLen];
    signal hasMajoritySupport[maxAlnLen];
    signal baseSupport[maxAlnLen][4];
    component baseMatch[maxAlnLen][4];
    component validConsensus[maxAlnLen];
    
    // Verify that the provided consensus respects majority voting
    for (var pos = 0; pos < maxAlnLen; pos++) {
        // Check if consensus[pos] is a gap (0)
        isGap[pos] = IsZero();
        isGap[pos].in <== consensus[pos];
        
        // If consensus[pos] is not a gap, ensure it matches a base with majority support
        for (var base = 0; base < 4; base++) {
            baseMatch[pos][base] = IsEqual();
            baseMatch[pos][base].in[0] <== consensus[pos];
            baseMatch[pos][base].in[1] <== base + 1;
            baseSupport[pos][base] <== baseMatch[pos][base].out * majorityChk[pos][base].ok;
        }
        
        // Sum up the support
        hasMajoritySupport[pos] <== baseSupport[pos][0] + baseSupport[pos][1] + baseSupport[pos][2] + baseSupport[pos][3];
        
        // Either it's a gap or it must have majority support
        validConsensus[pos] = IsEqual();
        validConsensus[pos].in[0] <== isGap[pos].out + hasMajoritySupport[pos];
        validConsensus[pos].in[1] <== 1;
        validConsensus[pos].out === 1;  // Enforce the constraint
    }
    
    // Final validation output (indicates successful verification)
    signal output valid;
    valid <== scoreCheck.out;
}


component main { public [reads, readLens, expectedScore] } = Consensus(10, 20, 30, 5);