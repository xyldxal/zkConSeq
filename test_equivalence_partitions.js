const fs = require('fs');
const { execSync } = require('child_process');
const path = require('path');

const BASE = { '-': 0, 'A': 1, 'C': 2, 'G': 3, 'T': 4 };

const testCases = [
    // 1. Perfect match – every base identical, no gaps
    {
      name: '1-all-perfect-match',
      description: '10 identical reads; no gaps or mismatches',
      seqs: [
        'ACTGACTG', 'ACTGACTG', 'ACTGACTG', 'ACTGACTG', 'ACTGACTG',
        'ACTGACTG', 'ACTGACTG', 'ACTGACTG', 'ACTGACTG', 'ACTGACTG'
      ],
      expectedResult: 'PASS'
    },
  
    // 2. Mismatches only – same length, no gaps
    {
      name: '2-mismatch-no-gap',
      description: 'Each read differs at 1-2 positions; no gaps',
      seqs: [
        'ACTGACTG', 'ACTGACCG', 'ACTGATCG', 'ACTGACTA', 'ACTTACTG',
        'ACC GACTG'.replace(' ','T'), // ACTTGACTG
        'ACTGACTC', 'ACCGACTG', 'GCTGACTG', 'ACTAACTG'
      ],
      expectedResult: 'PASS'
    },
  
    // 3. Gaps only – insert/delete but no letter mismatches
    {
      name: '3-gaps-no-mismatch',
      description: 'Letters always match when present; gaps otherwise',
      seqs: [
        'A-C-TG--', 'A-C-TG--', 'A-C-TG--', 'A-C-TG--', 'A-C-TG--',
        'A--CTG--', 'A-C-TG--', 'A-C-TG--', 'A-C-TG--', 'A-C-TG--'
      ],
      expectedResult: 'PASS'
    },
  
    // 4. Gaps + mismatches
    {
      name: '4-gaps-and-mismatches',
      description: 'Mix of mismatches and gaps',
      seqs: [
        'A-TGAC--', 'AG-GAC--', 'ATGAAC--', 'A-TGTC--', 'AG-GTC--',
        'ATGATC--', 'A-TGAC--', 'AG-GAC--', 'ATGAAC--', 'A-TGTC--'
      ],
      expectedResult: 'PASS'
    },
  
    // 5. Leading / trailing gaps
    {
      name: '5-leading-trailing-gaps',
      description: 'Same core string, different gap padding',
      seqs: [
        '--ACTG', '-ACTG-', 'ACTG--', '--ACTG', '-ACTG-', 'ACTG--',
        '--ACTG', '-ACTG-', 'ACTG--', '--ACTG'
      ],
      expectedResult: 'PASS'
    },
  
    // 6. Unequal raw lengths before alignment
    {
      name: '6-unequal-lengths',
      description: 'Raw lengths 3–6 bases, aligned with gaps',
      seqs: [
        'A-C-T-',   // ACT
        'A-C-TG',   // ACTG
        'A-CGTT',   // ACGTTA
        'A-C-T-',   'A-C-TG',  'A-CGTT',
        'A-C-T-',   'A-C-TG',  'A-CGTT',  'A-C-T-'
      ],
      expectedResult: 'PASS'
    },
  
    // 7. Mixed: match + mismatch + gap
    {
      name: '7-mixed-complex',
      description: 'Contains all three event types',
      seqs: [
        'ATGC----', 'A-GA----', 'AT-C----', 'ATGA----', 'A-GC----',
        'ATG-----', 'A-GA----', 'AT-C----', 'ATGA----', 'A-GC----'
      ],
      expectedResult: 'PASS'
    },
  
    // 8. Minimal – single aligned position
    {
      name: '8-minimal-single-base',
      description: 'One aligned column; rest padded by script',
      seqs: [ 'A', 'A', 'A', 'A', 'A', 'A', 'A', 'A', 'A', 'A' ],
      expectedResult: 'PASS'
    }
  ];

function encodeSequence(str) {
    return [...str].map(c => BASE[c] || 0);
}

function calculatePairwiseScore(seq1, seq2) {
    let score = 0;
    const minLen = Math.min(seq1.length, seq2.length);
    
    for (let i = 0; i < minLen; i++) {
        const [a, b] = [seq1[i], seq2[i]];
        
        if (a === 0 && b === 0) {
            // Both gaps - no penalty/reward
            continue;
        } else if (a !== 0 && b !== 0 && a === b) {
            // Match
            score += 1;
        } else {
            // Mismatch or gap vs base
            score -= 1;
        }
    }
    
    return score;
}

function prepareInput(testCase) {
    const nReadsFixed = 10;
    const maxSeqLen = 20;
    const maxAlnLen = 30;
    
    console.log(`\n🔧 Preparing input for: ${testCase.name}`);
    console.log(`   Description: ${testCase.description}`);
    console.log(`   Raw sequences: [${testCase.seqs.map(s => `"${s}"`).join(', ')}]`);
    
    // Step 1: Process aligned reads (with gaps)
    const alignedReadsRaw = testCase.seqs.map(seq => {
        // Pad or truncate to maxAlnLen
        return seq.padEnd(maxAlnLen, '-').slice(0, maxAlnLen);
    });
    
    const alignedReads = alignedReadsRaw.map(encodeSequence);
    console.log(`   Aligned reads (encoded): ${alignedReads.length} sequences`);
    
    // Step 2: Process raw reads (gaps removed)
    const readsRaw = testCase.seqs.map(seq => {
        const noGaps = seq.replace(/-/g, '');
        return noGaps.padEnd(maxSeqLen, '-').slice(0, maxSeqLen);
    });
    
    const reads = readsRaw.map(encodeSequence);
    const readLens = testCase.seqs.map(seq => seq.replace(/-/g, '').length);
    
    console.log(`   Raw reads (no gaps): [${readsRaw.map(s => `"${s}"`).join(', ')}]`);
    console.log(`   Read lengths: [${readLens.join(', ')}]`);
    
    // Step 3: Pad with dummy reads
    const nReads = testCase.seqs.length;
    while (alignedReads.length < nReadsFixed) {
        alignedReads.push(Array(maxAlnLen).fill(0));
        reads.push(Array(maxSeqLen).fill(0));
        readLens.push(0);
    }
    
    // Step 4: Calculate expected score (include dummy gap-only reads to
    // keep consistency with circuit which iterates over a fixed nReads)
    const totalReads = alignedReads.length; // == nReadsFixed
    let expectedScore = 0;
    for (let i = 0; i < totalReads; i++) {
        for (let j = i + 1; j < totalReads; j++) {
            expectedScore += calculatePairwiseScore(alignedReads[i], alignedReads[j]);
        }
    }
    console.log(`   🎯 Expected total score (with dummy reads): ${expectedScore}`);
    
    // Step 5: Create input object
    const input = {
        reads: reads,
        readLens: readLens,
        expectedScore: expectedScore,
        alignedReads: alignedReads,
        isReversed: Array(nReadsFixed).fill(0),
        startPos: Array(nReadsFixed).fill(0),
        consensus: Array(maxAlnLen).fill(0) // Placeholder
    };
    
    return { input, expectedScore, nReads };
}

async function runSingleTest(testCase, index) {
    console.log(`\n${'='.repeat(60)}`);
    console.log(`🧪 Test ${index + 1}/${testCases.length}: ${testCase.name}`);
    console.log(`${'='.repeat(60)}`);
    
    try {
        // Step 1: Prepare input
        const { input, expectedScore, nReads } = prepareInput(testCase);
        
        // Step 2: Save input and validate JSON
        const inputFile = `input_${testCase.name}.json`;
        fs.writeFileSync(inputFile, JSON.stringify(input, null, 2));
        console.log(`   ✅ Input saved to ${inputFile}`);
        
        // Step 3: Validate input can be parsed back
        const parsedInput = JSON.parse(fs.readFileSync(inputFile));
        console.log(`   ✅ Input validation passed`);
        
        // Step 4: Generate witness with detailed error reporting
        const witnessFile = `witness_${testCase.name}.wtns`;
        console.log(`   🔄 Generating witness...`);
        
        try {
            execSync(
                `snarkjs wtns calculate GenomicConsensus_js/GenomicConsensus.wasm ${inputFile} ${witnessFile}`,
                { stdio: 'pipe', encoding: 'utf-8' }
            );
            console.log(`   ✅ Witness generated: ${witnessFile}`);
        } catch (witnessError) {
            console.log(`   ❌ Witness generation FAILED:`);
            console.log(`      Error: ${witnessError.message}`);
            if (witnessError.stdout) console.log(`      Stdout: ${witnessError.stdout}`);
            if (witnessError.stderr) console.log(`      Stderr: ${witnessError.stderr}`);
            throw new Error('Witness generation failed');
        }
        
        // Step 5: Generate proof
        const proofFile = `proof_${testCase.name}.json`;
        const publicFile = `public_${testCase.name}.json`;
        
        console.log(`   🔄 Generating proof...`);
        execSync(
            `snarkjs groth16 prove circuit_final.zkey ${witnessFile} ${proofFile} ${publicFile}`,
            { stdio: 'pipe' }
        );
        console.log(`   ✅ Proof generated: ${proofFile}`);
        
        // Step 6: Verify proof
        console.log(`   🔄 Verifying proof...`);
        execSync(
            `snarkjs groth16 verify verification_key.json ${publicFile} ${proofFile}`,
            { stdio: 'pipe' }
        );
        console.log(`   ✅ Proof verification passed`);
        
        // Step 7: Proof verified => treat as valid
        const isValid = true;
        // Display basic stats
        console.log(`   📊 Results:`);
        console.log(`      - Expected score: ${expectedScore}`);
        console.log(`      - Active sequences: ${nReads}`);
        console.log(`      - Proof verification: SUCCESS`);
        console.log(`      - Expected result label: ${testCase.expectedResult}`);
        
        // Step 8: Cleanup (optional - comment out for debugging)
        const cleanupFiles = [inputFile, witnessFile, proofFile, publicFile];
        // cleanupFiles.forEach(f => fs.existsSync(f) && fs.unlinkSync(f));
        
        return {
            success: true,
            isValid: isValid,
            expectedScore: expectedScore,
            nReads: nReads
        };
        
    } catch (error) {
        console.log(`   ❌ Test FAILED: ${error.message}`);
        return {
            success: false,
            error: error.message
        };
    }
}

async function runAllTests() {
    console.log('🧬 ZKP Genomic Consensus - Equivalence Partition Testing');
    console.log('=========================================================');
    
    const results = [];
    
    for (let i = 0; i < testCases.length; i++) {
        const result = await runSingleTest(testCases[i], i);
        results.push({
            testCase: testCases[i],
            ...result
        });
        
        // Small delay between tests
        await new Promise(resolve => setTimeout(resolve, 100));
    }
    
    // Summary
    console.log(`\n${'='.repeat(60)}`);
    console.log('📋 TEST SUMMARY');
    console.log(`${'='.repeat(60)}`);
    
    results.forEach((result, i) => {
        const status = result.success ? '✅' : '❌';
        const validity = result.success ? (result.isValid ? 'VALID' : 'INVALID') : 'ERROR';
        console.log(`${status} ${i + 1}. ${result.testCase.name}: ${validity}`);
        if (!result.success) {
            console.log(`   Error: ${result.error}`);
        }
    });
    
    const passCount = results.filter(r => r.success).length;
    console.log(`\n🎯 Overall: ${passCount}/${results.length} tests completed successfully`);
}

// Run if called directly
if (require.main === module) {
    runAllTests().catch(console.error);
}

module.exports = { runAllTests, runSingleTest };