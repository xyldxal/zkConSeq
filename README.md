# Zero-Knowledge Proof Implementation for Consensus Sequence Generation Using Circom

A zero-knowledge proof circuit for genomic consensus sequence generation with multiple sequence alignment (MSA) validation, implemented in Circom.

## 🧬 Overview

This circuit enables privacy-preserving validation of genomic consensus sequences by proving that:
1. **Alignment Correctness**: Aligned reads correspond to original reads (with gaps removed)
2. **Score Accuracy**: MSA pairwise alignment score matches expected value  
3. **Consensus Validity**: Consensus sequence is generated via majority voting
4. **SNP Handling**: Single nucleotide polymorphisms are correctly processed via majority vote

All while keeping the alignment strategy private.

## ✅ Verification Status

- **Circuit Compilation**: ✅ Successfully compiles (31,959 constraints)
- **Benchmark Scenario**: ✅ 10 reads (9 identical + 1 variant) → Consensus & score validated
- **Complex Scenario**: ✅ 4 identical + 1 SNP → Majority consensus  
- **Proof Generation**: ✅ Zero-knowledge proofs generated
- **Proof Verification**: ✅ All proofs verify with `snarkJS: OK!`

## Circuit Architecture

**Public Inputs:**
- `reads[10][20]`: Raw DNA sequences (padded)
- `readLens[10]`: Actual sequence lengths
- `expectedScore`: Expected MSA alignment score

**Private Inputs:**
- `alignedReads[10][30]`: Gapped alignment strings
- `isReversed[10]`: Reverse complement flags
- `startPos[10]`: Sliding alignment positions

**Outputs:**
- `consensus[30]`: Generated consensus sequence (private)
- `valid`: 1 if all validations pass


## Parameter Tuning

The circuit is parameterised as

```circom
component main { public [reads, readLens, expectedScore] } =
    Consensus(nReads, maxSeqLen, maxAlnLen, threshold);
```

Change these four integers to scale the circuit, then re-compile and re-run the setup/witness/proof steps.  The default configuration used throughout this repo and benchmarks is:

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| `nReads` | **10** | keeps pairwise score validation ( 45 pairs ) lightweight |
| `maxSeqLen` | **20** | covers typical short-read experiments |
| `maxAlnLen` | **30** | allows gaps / indels while staying compact |
| `threshold` | **5** | simple majority ( > 50 %) for 10 reads |

This preset finishes trusted-setup in minutes and generates proofs in a few seconds on a laptop.  Larger settings (e.g. 40 reads, 100 bp alignments) are supported but will grow constraints roughly as 𝑂(n²·maxAlnLen).

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

- **Constraints:** 22,672 non-linear + 9,287 linear
- **Public inputs:** 211
- **Private inputs:** 350
- **Public outputs:** 1
- **Template instances:** 12

## Paper Overview  
*(see `latex/consensus.tex` for the full manuscript — work in progress)*

* **Abstract & Motivation** – introduces **zkConsensus**, a Circom circuit that proves a consensus sequence was correctly built from DNA reads without revealing the alignment.
* **Methodology** – details the three validation stages implemented in this repo:
  1. *Sequence Validation* – each gapped alignment must reduce to the original read (with optional reverse-complement handling), implemented by `SequenceMatch`.
  2. *Scoring Validation* – all  pairwise alignments are scored with +1/0/-1 rules (`ScoringSystem` & `PairScore`) and summed; the total must equal the public `expectedScore`.
  3. *Consensus Validation* – majority voting (> `threshold`) across reads to justify every base in the private `consensus` string.
* **Results (Table 1)** – shows constraint growth for four parameter sets; the default 10-read preset yields **31 959** constraints (22 672 nonlinear + 9 287 linear).
* **Discussion / Future Work** – suggests optimising non-linear gadgets, scaling to longer genomes, and adding ambiguous-base support.

---

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
