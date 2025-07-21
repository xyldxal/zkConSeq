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
    exit 1
fi

echo "📋 Circuit Statistics:"
echo "   - Constraints: ~13,327 non-linear + 4,518 linear"
echo "   - Public inputs: 106"
echo "   - Private inputs: 260"
echo ""

# Step 1: Powers of Tau Ceremony
echo "🔧 Step 1: Powers of Tau Ceremony"
echo "Generating universal trusted setup (this may take a few minutes)..."

# Use circuit size to determine ceremony size (17845*2 = 35690 constraints, need 2^16 = 65536)
CEREMONY_SIZE=16

if [ ! -f "powersOfTau28_hez_final_${CEREMONY_SIZE}.ptau" ]; then
    echo "Downloading Powers of Tau file..."
    wget https://hermez.s3-eu-west-1.amazonaws.com/powersOfTau28_hez_final_${CEREMONY_SIZE}.ptau
    
    if [ $? -ne 0 ]; then
        echo "Download failed. Generating locally..."
        snarkjs powersoftau new bn128 ${CEREMONY_SIZE} pot${CEREMONY_SIZE}_0000.ptau -v
        snarkjs powersoftau contribute pot${CEREMONY_SIZE}_0000.ptau pot${CEREMONY_SIZE}_0001.ptau --name="GenomicConsensus contribution" -v -e="genomic consensus zkp $(date)"
        snarkjs powersoftau prepare phase2 pot${CEREMONY_SIZE}_0001.ptau powersOfTau28_hez_final_${CEREMONY_SIZE}.ptau -v
    fi
fi

echo "✅ Powers of Tau ceremony completed"

# Step 2: Circuit-specific setup
echo ""
echo "🔧 Step 2: Circuit-specific Setup"
echo "Generating proving and verification keys..."

snarkjs groth16 setup GenomicConsensus.r1cs powersOfTau28_hez_final_${CEREMONY_SIZE}.ptau circuit_0000.zkey

if [ $? -ne 0 ]; then
    echo "❌ Circuit setup failed. Check Powers of Tau ceremony size."
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
echo "   - Powers of Tau: powersOfTau28_hez_final_${CEREMONY_SIZE}.ptau"

# Step 5: Test with sample witness
echo ""
echo "🧪 Testing Setup"
if [ -f "witness.wtns" ]; then
    echo "Found existing witness, generating test proof..."
    snarkjs groth16 prove circuit_final.zkey witness.wtns proof.json public.json
    
    echo "Verifying test proof..."
    snarkjs groth16 verify verification_key.json public.json proof.json
    
    if [ $? -eq 0 ]; then
        echo "✅ Test proof verified successfully!"
    else
        echo "❌ Test proof verification failed"
    fi
else
    echo "⚠️  No witness found. Run witness_generator.js first to test the full pipeline."
fi

echo ""
echo "🎉 Setup ceremony completed successfully!"
echo ""
echo "Next steps:"
echo "1. Run: node witness_generator.js"
echo "2. Generate proof: snarkjs groth16 prove circuit_final.zkey witness.wtns proof.json public.json"
echo "3. Verify proof: snarkjs groth16 verify verification_key.json public.json proof.json"
