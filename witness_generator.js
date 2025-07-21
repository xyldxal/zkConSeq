const snarkjs = require("snarkjs");
const fs = require("fs");

// Base encoding: A=1, C=2, G=3, T=4, Gap=0
const BASE_MAP = { 'A': 1, 'C': 2, 'G': 3, 'T': 4, '-': 0 };
const REV_MAP = { 1: 4, 2: 3, 3: 2, 4: 1, 0: 0 }; // A<->T, C<->G

function encodeSequence(seq, maxLen) {
    const encoded = seq.split('').map(base => BASE_MAP[base.toUpperCase()] || 0);
    // Pad with zeros to maxLen
    while (encoded.length < maxLen) encoded.push(0);
    return encoded.slice(0, maxLen);
}

function reverseComplement(encoded) {
    return encoded.slice().reverse().map(base => REV_MAP[base]);
}

function calculatePairwiseScore(aln1, aln2) {
    let score = 0;
    for (let i = 0; i < aln1.length; i++) {
        // Only score positions where both sequences have actual bases (not padding zeros)
        if (aln1[i] !== 0 && aln2[i] !== 0) {
            if (aln1[i] === aln2[i]) {
                score += 1; // Match
            } else {
                score -= 1; // Mismatch
            }
        }
        // Skip positions where either sequence has padding (0)
    }
    return score;
}

function calculateMSAScore(alignedReads) {
    let totalScore = 0;
    const nReads = alignedReads.length;
    
    for (let i = 0; i < nReads; i++) {
        for (let j = i + 1; j < nReads; j++) {
            totalScore += calculatePairwiseScore(alignedReads[i], alignedReads[j]);
        }
    }
    return totalScore;
}

function generateConsensus(alignedReads, threshold) {
    const alnLen = alignedReads[0].length;
    const nReads = alignedReads.length;
    const consensus = [];
    
    for (let pos = 0; pos < alnLen; pos++) {
        const counts = [0, 0, 0, 0, 0]; // counts for bases 0,1,2,3,4
        
        // Count bases at this position
        for (let r = 0; r < nReads; r++) {
            const base = alignedReads[r][pos];
            if (base >= 0 && base <= 4) counts[base]++;
        }
        
        // Find majority base (excluding gaps)
        let maxCount = 0;
        let winnerBase = 0;
        for (let b = 1; b <= 4; b++) {
            if (counts[b] > maxCount && counts[b] > threshold) {
                maxCount = counts[b];
                winnerBase = b;
            }
        }
        consensus.push(winnerBase);
    }
    return consensus;
}

// Sample genomic data
// Test scenarios: simple (identical) vs complex (with variations)
const useComplexScenario = true; // Set to true to test variations

const simpleData = {
    // Simple case: identical reads for initial testing
    rawReads: [
        "ATCGATCG",
        "ATCGATCG", 
        "ATCGATCG",
        "ATCGATCG",
        "ATCGATCG"
    ],
    alignedReads: [
        "ATCGATCG",
        "ATCGATCG",
        "ATCGATCG", 
        "ATCGATCG",
        "ATCGATCG"
    ],
    isReversed: [0, 0, 0, 0, 0],
    startPos: [0, 0, 0, 0, 0],
    expectedScore: 80,  // 10 pairs * 8 matches each
    expectedConsensus: "ATCGATCG"
};

const complexData = {
    // Complex case: realistic genomic alignment with gaps and sliding
    rawReads: [
        "ATCGATCG",    // Original sequence
        "TCGATCGA",    // Shifted by 2 positions
        "CGATCGAT",    // Shifted by 4 positions  
        "GATCGATC",    // Shifted by 6 positions
        "ATCGATCG"     // Same as original
    ],
    alignedReads: [
        "ATCGATCG------------------------------------------",  // Position 0
        "--TCGATCGA---------------------------------------",  // Position 2
        "----CGATCGAT-------------------------------------",  // Position 4
        "------GATCGATC-----------------------------------",  // Position 6
        "ATCGATCG------------------------------------------"   // Position 0
    ],
    isReversed: [0, 0, 0, 0, 0],
    startPos: [0, 2, 4, 6, 0],  // Sliding start positions
    expectedScore: 56,  // Calculated based on overlapping regions
    expectedConsensus: "ATCGATCGATCGATC"  // Overlapping consensus from sliding reads
};

const sampleData = useComplexScenario ? complexData : simpleData;

function generateWitnessInput() {
    const maxSeqLen = 20;
    const maxAlnLen = 50;
    const nReads = 5;
    const threshold = 2;
    
    // Encode raw reads
    const encodedReads = sampleData.rawReads.map(seq => encodeSequence(seq, maxSeqLen));
    const readLens = sampleData.rawReads.map(seq => seq.length);
    
    // Encode aligned reads
    const encodedAlignedReads = sampleData.alignedReads.map(seq => encodeSequence(seq, maxAlnLen));
    
    // Calculate expected MSA score
    const expectedScore = calculateMSAScore(encodedAlignedReads);
    
    // Generate expected consensus
    const expectedConsensus = generateConsensus(encodedAlignedReads, threshold);
    
    console.log("Generated witness input:");
    console.log("- Raw reads:", sampleData.rawReads);
    console.log("- Read lengths:", readLens);
    console.log("- Aligned reads:", sampleData.alignedReads);
    console.log("- Expected MSA score:", expectedScore);
    console.log("- Expected consensus:", expectedConsensus.map(b => Object.keys(BASE_MAP)[b-1] || '-').join(''));
    
    return {
        // Public inputs
        reads: encodedReads,
        readLens: readLens,
        expectedScore: expectedScore,
        
        // Private inputs
        alignedReads: encodedAlignedReads,
        isReversed: sampleData.isReversed,
        startPos: sampleData.startPos
    };
}

async function generateWitness() {
    try {
        console.log("Generating witness for GenomicConsensus circuit...");
        
        const input = generateWitnessInput();
        
        // Save input for debugging
        fs.writeFileSync("input.json", JSON.stringify(input, null, 2));
        console.log("Input saved to input.json");
        
        // Generate witness
        await snarkjs.wtns.calculate(input, "GenomicConsensus_js/GenomicConsensus.wasm", "witness.wtns");
        console.log("Witness generated successfully: witness.wtns");
        
        return true;
    } catch (error) {
        console.error("Error generating witness:", error);
        return false;
    }
}

// Export for use in other scripts
module.exports = {
    generateWitnessInput,
    generateWitness,
    encodeSequence,
    calculateMSAScore,
    generateConsensus
};

// Run if called directly
if (require.main === module) {
    generateWitness().then(success => {
        process.exit(success ? 0 : 1);
    });
}
