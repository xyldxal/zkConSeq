# GenomicConsensus ZKP Circuit

A zero-knowledge proof circuit for genomic consensus sequence generation with multiple sequence alignment (MSA) validation, implemented in Circom.

## 🧬 Overview

This circuit enables privacy-preserving validation of genomic consensus sequences by proving that:
1. **Alignment Correctness**: Aligned reads correspond to original reads (with gaps removed)
2. **Score Accuracy**: MSA pairwise alignment score matches expected value  
3. **Consensus Validity**: Consensus sequence is generated via majority voting
4. **SNP Handling**: Single nucleotide polymorphisms are correctly processed via majority vote

All while keeping the alignment strategy private.

## ✅ Verification Status

- **Circuit Compilation**: ✅ Successfully compiles (13,327 constraints)
- **Simple Scenario**: ✅ 5 identical reads → Perfect consensus
- **Complex Scenario**: ✅ 4 identical + 1 SNP → Majority consensus  
- **Proof Generation**: ✅ Zero-knowledge proofs generated
- **Proof Verification**: ✅ All proofs verify with `snarkJS: OK!`

## Circuit Architecture

**Public Inputs:**
- `reads[5][20]`: Raw DNA sequences (padded)
- `readLens[5]`: Actual sequence lengths
- `expectedScore`: Expected MSA alignment score

**Private Inputs:**
- `alignedReads[5][50]`: Gapped alignment strings
- `isReversed[5]`: Reverse complement flags
- `startPos[5]`: Sliding alignment positions

**Outputs:**
- `consensus[50]`: Generated consensus sequence
- `valid`: 1 if all validations pass
- `alignmentScore`: Computed MSA score

## Quick Start

### 1. Install Dependencies
```bash
npm install snarkjs circomlib
```

### 2. Compile Circuit
```bash
circom GenomicConsensus.circom --r1cs --wasm --sym
```

### 3. Run Setup Ceremony
```bash
chmod +x setup_ceremony.sh
./setup_ceremony.sh
```

### 4. Generate Witness & Proof
```bash
# Generate witness from sample data
node witness_generator.js

# Generate proof
snarkjs groth16 prove circuit_final.zkey witness.wtns proof.json public.json

# Verify proof
snarkjs groth16 verify verification_key.json public.json proof.json
```

### 5. Run Full Test Suite
```bash
node test_proof.js
```

## Circuit Statistics

- **Constraints:** 13,327 non-linear + 4,518 linear
- **Public inputs:** 106
- **Private inputs:** 260
- **Public outputs:** 52
- **Template instances:** 12

## File Structure

```
zkConSeq/
├── GenomicConsensus.circom     # Main circuit
├── witness_generator.js        # Sample data & witness generation
├── setup_ceremony.sh          # Trusted setup script
├── test_proof.js              # Full pipeline testing
├── package.json               # Node.js dependencies
└── README.md                  # This file
```

## Usage Examples

### Custom Input Data

```javascript
const input = {
    reads: [
        [1,2,3,4,0,0,...], // ATCG + padding
        [2,3,4,1,0,0,...], // CGTA + padding
        // ... more reads
    ],
    readLens: [4, 4, 4, 4, 4],
    expectedScore: 15,
    alignedReads: [
        [1,2,3,4,0,0,...], // Gapped alignment
        // ... aligned versions
    ],
    isReversed: [0, 1, 0, 0, 1],
    startPos: [0, 2, 1, 0, 3]
};
```

### Web Integration

```javascript
const snarkjs = require("snarkjs");

// Verify proof in browser/Node.js
const vKey = await fetch("verification_key.json").then(r => r.json());
const proof = await fetch("proof.json").then(r => r.json());
const publicSignals = await fetch("public.json").then(r => r.json());

const isValid = await snarkjs.groth16.verify(vKey, publicSignals, proof);
console.log("Proof valid:", isValid);
```

### Smart Contract Deployment

```solidity
// Use generated GenomicConsensusVerifier.sol
contract GenomicConsensusApp {
    GenomicConsensusVerifier immutable verifier;
    
    function verifyConsensus(
        uint[2] memory _pA,
        uint[2][2] memory _pB,
        uint[2] memory _pC,
        uint[] memory _pubSignals
    ) public view returns (bool) {
        return verifier.verifyProof(_pA, _pB, _pC, _pubSignals);
    }
}
```

## Integration Examples

### Web Application
```javascript
const snarkjs = require("snarkjs");

// Load verification key
const vKey = await fetch("/verification_key.json").then(r => r.json());

// Verify proof from client
const isValid = await snarkjs.groth16.verify(vKey, publicSignals, proof);
if (isValid) {
    console.log("Consensus proof verified!");
    // Extract consensus from public signals
    const consensus = extractConsensus(publicSignals);
}
```

### Smart Contract Integration
```solidity
import "./GenomicConsensusVerifier.sol";

contract GenomicRegistry {
    GenomicConsensusVerifier immutable verifier;
    
    function submitConsensus(
        uint[2] memory _pA,
        uint[2][2] memory _pB, 
        uint[2] memory _pC,
        uint[] memory _pubSignals
    ) public {
        require(verifier.verifyProof(_pA, _pB, _pC, _pubSignals), "Invalid proof");
        // Store verified consensus...
    }
}
```

## Base Encoding

- A = 1, C = 2, G = 3, T = 4
- Gap = 0
- Reverse complements: A↔T, C↔G

## Troubleshooting

**Circuit compilation fails:**
- Ensure circom 2.2.2+ installed
- Check circomlib dependency

**Witness generation fails:**
- Verify input array dimensions match circuit parameters
- Check base encoding (1-4 for ATCG, 0 for gaps)

**Proof verification fails:**
- Ensure setup ceremony completed successfully
- Verify witness matches circuit constraints
- Check public/private input separation

## Performance

- **Proof generation:** ~10-30 seconds
- **Verification:** <100ms
- **Memory usage:** ~2GB during setup
- **Proof size:** ~1KB

## Contributing

This circuit implements the MSA validation requirements from academic research on zero-knowledge genomics. For modifications:

1. Update circuit parameters in `GenomicConsensus.circom`
2. Regenerate setup with `./setup_ceremony.sh`
3. Test with `node test_proof.js`

## License

MIT License - See LICENSE file for details. 
