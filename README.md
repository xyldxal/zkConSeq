# zkConsensus: A Zero-Knowledge Proof Implementation for Consensus Sequence Generation

A zero-knowledge proof circuit for genomic consensus sequence generation with multiple sequence alignment (MSA) validation, implemented in Circom.

This Circom circuit enables privacy-preserving validation of genomic consensus sequences by proving that (1) aligned reads correspond to original reads upon removal of gaps, (2) MSA pairwise alignment scores match expected values, and (3) consensus sequence is generated via majority voting. All while keeping the aligned reads, reverse complement flags, and sliding alignment positions, and the actual consensus sequence itself private.

---

## Circuit Architecture

**Public Inputs:**
- `reads[nReads][maxSeqLen]`: Raw DNA sequences (padded)
- `readLens[nReads]`: Actual sequence lengths
- `expectedScore`: Expected MSA alignment score

**Private Inputs:**
- `alignedReads[nReads][maxAlnLen]`: Gapped alignment strings
- `isReversed[nReads]`: Reverse complement flags
- `startPos[nReads]`: Sliding alignment positions

**Outputs:**
- `consensus[maxSeqLen]`: Generated consensus sequence (private)
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

## Usage

### 1. Install dependencies
```bash
npm install snarkjs circomlib
```

### 2. Compile circuit 
```bash
circom GenomicConsensus.circom --r1cs --wasm --sym
```

### 3. Run setup ceremony
On bash:
```bash
chmod +x setup_ceremony.sh
./setup_ceremony.sh
```

### 4. Generate witness & proof
```bash
# Generate witness from sample data
node witness_generator.js

# Generate proof
snarkjs groth16 prove circuit_final.zkey witness.wtns proof.json public.json

# Verify proof
snarkjs groth16 verify verification_key.json public.json proof.json
```

### 5. Run core test suite
On bash:
```bash
node test_proof.js
```

### 6. Run equivalence partition tests
`test_equivalence_partitions.js` executes eight representative read sets that exercise all major alignment edge-cases (perfect match, mismatches, gaps, mixed events, length variations, etc.).  Proof generation and verification should succeed for every partition when the circuit parameters remain at the default
preset (10, 20, 30, 5).

```bash
node test_equivalence_partitions.js
```

Verifying proof for specific test case:
```bash
#testCases:
#    '1-all-perfect-match',
#    '2-mismatch-no-gap',
#    '3-gaps-no-mismatch',
#    '4-gaps-and-mismatches',
#    '5-leading-trailing-gaps',
#    '6-unequal-lengths',
#    '7-mixed-complex',
#    '8-minimal-single-base'

#CASE=1-all-perfect-match, change to any test case
snarkjs groth16 verify verification_key.json public_${CASE}.json proof_${CASE}.json
```
## Paper Details  
Paper to be submitted to *TBA*.

* **Abstract** – introduces **zkConsensus**, a Circom circuit that proves a consensus sequence was correctly built from DNA reads without revealing alignment details and the actual consensus sequence.
* **Methodology** – details the three validation stages implemented in this repo:
  1. *Sequence Validation* – each gapped alignment must reduce to the original read (with optional reverse-complement handling), implemented by `SequenceMatch`.
  2. *Scoring Validation* – all  pairwise alignments are scored with +1/0/-1 rules (`ScoringSystem` & `PairScore`) and summed; the total must equal the public `expectedScore`.
  3. *Consensus Validation* – majority voting (> `threshold`) across reads to justify every base in the private `consensus` string.
* **Results** – shows constraint growth for four parameter sets, which has linear proportionality on sequence validation, then quadratic in scoring validation, and not quadratic but multiplicative upon consensus validation. Overall, fitting the three validation stages into a single circuit brings challenges in terms of scalability and performance. However, a witness, proof, and verification process can be generated for the first parameter set in a matter of seconds.
---

## File Structure

```
zkConSeq/
├── GenomicConsensus.circom     # Main circuit
├── witness_generator.js        # Sample data & witness generation
├── setup_ceremony.sh          # Trusted setup script
├── test_proof.js              # Full pipeline testing
├── test_equivalence_partitions.js # Equivalence partition testing
└── README.md                  # This file
```
