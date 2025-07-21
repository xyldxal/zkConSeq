const snarkjs = require("snarkjs");
const fs = require("fs");
const { generateWitnessInput } = require("./witness_generator");

async function testFullPipeline() {
    console.log("🧬 GenomicConsensus ZKP Full Pipeline Test");
    console.log("=========================================");
    
    try {
        // Step 1: Generate witness
        console.log("\n📝 Step 1: Generating witness...");
        const input = generateWitnessInput();
        
        if (!fs.existsSync("GenomicConsensus_js/GenomicConsensus.wasm")) {
            throw new Error("WASM file not found. Please compile circuit first.");
        }
        
        await snarkjs.wtns.calculate(input, "GenomicConsensus_js/GenomicConsensus.wasm", "witness.wtns");
        console.log("✅ Witness generated: witness.wtns");
        
        // Step 2: Generate proof
        console.log("\n🔐 Step 2: Generating proof...");
        if (!fs.existsSync("circuit_final.zkey")) {
            throw new Error("Circuit key not found. Please run setup ceremony first.");
        }
        
        await snarkjs.groth16.prove("circuit_final.zkey", "witness.wtns", "proof.json", "public.json");
        console.log("✅ Proof generated: proof.json, public.json");
        
        // Step 3: Verify proof
        console.log("\n✅ Step 3: Verifying proof...");
        if (!fs.existsSync("verification_key.json")) {
            throw new Error("Verification key not found. Please run setup ceremony first.");
        }
        
        const vKey = JSON.parse(fs.readFileSync("verification_key.json"));
        const proof = JSON.parse(fs.readFileSync("proof.json"));
        const publicSignals = JSON.parse(fs.readFileSync("public.json"));
        
        const res = await snarkjs.groth16.verify(vKey, publicSignals, proof);
        
        if (res) {
            console.log("🎉 Proof verification SUCCESSFUL!");
            
            // Display proof details
            console.log("\n📊 Proof Details:");
            console.log(`   - Public inputs: ${publicSignals.length}`);
            console.log(`   - Proof size: ${JSON.stringify(proof).length} bytes`);
            console.log(`   - Verification key size: ${JSON.stringify(vKey).length} bytes`);
            
            // Parse some public outputs
            const nReads = 5;
            const maxSeqLen = 20;
            const maxAlnLen = 50;
            
            // Extract consensus from public signals (last 50 values before valid/score)
            const consensusStart = nReads * maxSeqLen + nReads + 1; // after reads, readLens, expectedScore
            const consensus = publicSignals.slice(consensusStart, consensusStart + maxAlnLen);
            const valid = publicSignals[publicSignals.length - 2];
            const alignmentScore = publicSignals[publicSignals.length - 1];
            
            console.log("\n🧬 Results:");
            console.log(`   - Consensus: ${consensus.map(b => ['', 'A', 'C', 'G', 'T'][b] || '-').join('')}`);
            console.log(`   - Valid: ${valid === '1' ? 'YES' : 'NO'}`);
            console.log(`   - Alignment Score: ${alignmentScore}`);
            
        } else {
            console.log("❌ Proof verification FAILED!");
            return false;
        }
        
        // Step 4: Performance metrics
        console.log("\n⚡ Performance Metrics:");
        const proofStats = fs.statSync("proof.json");
        const witnessStats = fs.statSync("witness.wtns");
        
        console.log(`   - Witness file size: ${(witnessStats.size / 1024).toFixed(2)} KB`);
        console.log(`   - Proof file size: ${(proofStats.size / 1024).toFixed(2)} KB`);
        
        return true;
        
    } catch (error) {
        console.error("❌ Pipeline test failed:", error.message);
        return false;
    }
}

async function benchmarkProofGeneration() {
    console.log("\n🏃 Benchmarking proof generation...");
    
    const iterations = 3;
    const times = [];
    
    for (let i = 0; i < iterations; i++) {
        console.log(`   Run ${i + 1}/${iterations}...`);
        const start = Date.now();
        
        await snarkjs.groth16.prove("circuit_final.zkey", "witness.wtns", `proof_${i}.json`, `public_${i}.json`);
        
        const end = Date.now();
        times.push(end - start);
        
        // Clean up
        fs.unlinkSync(`proof_${i}.json`);
        fs.unlinkSync(`public_${i}.json`);
    }
    
    const avgTime = times.reduce((a, b) => a + b, 0) / times.length;
    console.log(`   Average proof generation time: ${(avgTime / 1000).toFixed(2)} seconds`);
    console.log(`   Min: ${(Math.min(...times) / 1000).toFixed(2)}s, Max: ${(Math.max(...times) / 1000).toFixed(2)}s`);
}

// Run tests
if (require.main === module) {
    testFullPipeline().then(async (success) => {
        if (success) {
            await benchmarkProofGeneration();
            console.log("\n🎯 All tests completed successfully!");
        }
        process.exit(success ? 0 : 1);
    });
}

module.exports = { testFullPipeline, benchmarkProofGeneration };
