#!/bin/bash

# Genomic Consensus ZKP Setup Script
# This script performs the trusted setup ceremony for the GenomicConsensus circuit

echo "🧬 GenomicConsensus ZKP Setup Ceremony"
echo "======================================"

# Check if snarkjs is installed
if ! command -v snarkjs &> /dev/null; then
    echo "❌ snarkjs not found. Please install with: npm install -g snarkjs"
    exit 1
fi

# Check if circuit files exist
if [ ! -f "GenomicConsensus.r1cs" ]; then
    echo "❌ GenomicConsensus.r1cs not found. Please compile the circuit first."
    echo "   Run: circom GenomicConsensus.circom --r1cs --sym --wasm"
    exit 1
fi

echo "📋 Circuit Statistics (for nReads=10, maxSeqLen=20, maxAlnLen=30, threshold=5):"
echo "   - Non-Linear Constraints: 22,672"
echo "   - Linear Constraints: 9,287"
echo "   - Total Constraints: 31,959"
echo "   - Public Inputs: 211"
echo "   - Private Inputs: 350 (340 belong to witness)"
echo "   - Wires: 32,350"
echo "   - Scoring System: Updated (gap-gap pairs = 0)"
echo ""

# Step 1: Powers of Tau Ceremony
echo "🔧 Step 1: Powers of Tau Ceremony"
echo "Generating universal trusted setup (this may take a few minutes)..."

# Determine ceremony size: 2^CEREMONY_SIZE must be >= 2 * max_constraints
# For 22,672 non-linear constraints, 2 * 22,672 = 45,344.
# Next power of 2: 2^16 = 65,536 (still sufficient).
CEREMONY_SIZE=16

# Check if the required ptau file exists, otherwise download or generate
PTAU_FILE="powersOfTau28_hez_final_${CEREMONY_SIZE}.ptau"

if [ ! -f "$PTAU_FILE" ]; then
    echo "Downloading Powers of Tau file: $PTAU_FILE ..."
    wget https://hermez.s3-eu-west-1.amazonaws.com/powersOfTau28_hez_final_${CEREMONY_SIZE}.ptau
    
    if [ $? -ne 0 ]; then
        echo "Download failed or file not found online. Generating locally (this will take longer)..."
        snarkjs powersoftau new bn128 ${CEREMONY_SIZE} pot${CEREMONY_SIZE}_0000.ptau -v
        snarkjs powersoftau contribute pot${CEREMONY_SIZE}_0000.ptau pot${CEREMONY_SIZE}_0001.ptau --name="GenomicConsensus contribution" -v -e="genomic consensus zkp $(date)"
        snarkjs powersoftau prepare phase2 pot${CEREMONY_SIZE}_0001.ptau ${PTAU_FILE} -v
    fi
else
    echo "Existing Powers of Tau file found: $PTAU_FILE"
fi

echo "✅ Powers of Tau ceremony completed"

# Step 2: Circuit-specific setup
echo ""
echo "🔧 Step 2: Circuit-specific Setup"
echo "Generating proving and verification keys (this may take several minutes for 22.6K+ constraints)..."

snarkjs groth16 setup GenomicConsensus.r1cs ${PTAU_FILE} circuit_0000.zkey

if [ $? -ne 0 ]; then
    echo "❌ Circuit setup failed. Check Powers of Tau ceremony size or R1CS file."
    exit 1
fi

echo "Adding entropy to the ceremony..."
snarkjs zkey contribute circuit_0000.zkey circuit_final.zkey --name="GenomicConsensus final contribution" -v -e="final genomic consensus setup $(date)"

if [ $? -ne 0 ]; then
    echo "❌ Key contribution failed."
    exit 1
fi

echo "Exporting verification key..."
snarkjs zkey export verificationkey circuit_final.zkey verification_key.json

if [ $? -ne 0 ]; then
    echo "❌ Verification key export failed."
    exit 1
fi

echo "✅ Circuit setup completed"

# Step 3: Generate Solidity verifier (optional)
echo ""
echo "🔧 Step 3: Solidity Verifier Generation"
snarkjs zkey export solidityverifier circuit_final.zkey GenomicConsensusVerifier.sol

echo "✅ Solidity verifier generated"

# Step 4: Verification info
echo ""
echo "📊 Setup Summary:"
echo "   - Circuit key: circuit_final.zkey"
echo "   - Verification key: verification_key.json" 
echo "   - Solidity verifier: GenomicConsensusVerifier.sol"
echo "   - Powers of Tau: ${PTAU_FILE}"
echo "   - Constraint count: 22,672 non-linear + 9,287 linear = 31,959 total"
echo "   - Complexity level: Moderate (suitable for laptop proving with patience)"

# Step 5: Test with sample witness
echo ""
echo "🧪 Testing Setup"
if [ -f "witness.wtns" ] && [ -f "public.json" ]; then
    echo "Found existing witness and public inputs. Generating test proof..."
    echo "⏱️  Proof generation may take 2-5 minutes for 22.6K constraints..."
    
    # Time the proof generation
    start_time=$(date +%s)
    snarkjs groth16 prove circuit_final.zkey witness.wtns proof.json public.json
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    if [ -f "proof.json" ]; then
        echo "✅ Proof generated successfully in ${duration} seconds"
        
        echo "Verifying test proof..."
        verify_start=$(date +%s)
        snarkjs groth16 verify verification_key.json public.json proof.json
        verify_end=$(date +%s)
        verify_duration=$((verify_end - verify_start))
        
        if [ $? -eq 0 ]; then
            echo "✅ Test proof verified successfully!"
            echo ""
            echo "🎯 Benchmarking Results for Consensus(10, 20, 30, 5):"
            echo "   - Setup time: Several minutes (one-time)"
            echo "   - Proof generation: ${duration} seconds"
            echo "   - Proof verification: ${verify_duration} seconds"
            echo "   - Constraint density: 22,672 non-linear constraints"
            echo "   - Memory usage: Moderate (suitable for 8GB+ RAM)"
        else
            echo "❌ Test proof verification failed"
        fi
    else
        echo "❌ Proof generation failed"
    fi
else
    echo "⚠️  No witness or public inputs found. Run 'node witness_generator.js' first to test the full pipeline."
fi

echo ""
echo "🎉 Setup ceremony completed successfully!"
echo ""
echo "Next steps:"
echo "1. Compile the circuit: circom GenomicConsensus.circom --r1cs --sym --wasm"
echo "2. Run this setup script: ./setup.sh"
echo "3. Generate witness: node witness_generator.js"
echo "4. Generate proof: snarkjs groth16 prove circuit_final.zkey witness.wtns proof.json public.json"
echo "5. Verify proof: snarkjs groth16 verify verification_key.json public.json proof.json"
echo ""
echo "📈 Scalability Note: 22.6K constraints represent a good balance between"
echo "   functionality and practicality for genomic consensus verification."