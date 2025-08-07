const snarkjs = require("snarkjs");
const fs = require("fs");
const { generateWitness } = require("./witness_generator");

const { execSync } = require("child_process");

async function testFullPipeline() {
    console.log("🧬 GenomicConsensus ZKP Full Pipeline Test");
    console.log("=========================================");
    
    try {
        // Step 1: Generate witness (writes witness.wtns & input.json internally)
        console.log("\n📝 Step 1: Generating witness via witness_generator.js ...");
        await generateWitness();
        if (!fs.existsSync("witness.wtns")) {
            throw new Error("witness.wtns not found; witness generation failed.");
        }
        console.log("✅ Witness generated: witness.wtns");
        
        // Step 2: Generate proof via snarkjs CLI to avoid API logger quirks
        console.log("\n🔐 Step 2: Generating proof via snarkjs CLI...");
        if (!fs.existsSync("circuit_final.zkey")) {
            throw new Error("Circuit key not found. Please run setup ceremony first.");
        }
        const { execSync } = require("child_process");
        execSync("snarkjs groth16 prove circuit_final.zkey witness.wtns proof.json public.json", { stdio: 'inherit' });
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
            console.log("✔ All validations satisfied: YES");
            
            // Display proof details
            console.log("\n📊 Proof Details:");
            console.log(`   - Public inputs: ${publicSignals.length}`);
            console.log(`   - Proof size: ${JSON.stringify(proof).length} bytes`);
            
            // Parse some public outputs
            const nReads = 10;
            const maxSeqLen = 20;
            
            // Uncomment next two lines if you want to inspect all public signals
            // console.log("\n Full publicSignals dump:");
            // console.log(publicSignals);
            const expectedScore = publicSignals[publicSignals.length - 1];
            console.log("\n Result:");
            console.log(`   - expectedScore (public): ${expectedScore}`);
            // The circuit does not expose a separate valid flag; successful Groth16 verification means all constraints hold.
            
        } else {
            console.log(" Proof verification FAILED!");
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
        
        execSync(`snarkjs groth16 prove circuit_final.zkey witness.wtns proof_${i}.json public_${i}.json`, { stdio: 'inherit' });
        
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
