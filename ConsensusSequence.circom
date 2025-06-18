pragma circom 2.2.2;

include "node_modules/circomlib/circuits/poseidon.circom";
include "node_modules/circomlib/circuits/comparators.circom";


template BaseProcessor() {
    signal input min_qual;
    signal input base;        // Encoded base (0-4)
    signal input qual;        // Quality score (Phred)
    signal input ref_pos;     // Reference position (private)
    signal input is_reverse;  // 0=forward, 1=reverse (private)
    signal input in_primer;   // 1=in primer region, 0=not (public)
    
    signal output count;      // 1 if should count, else 0
    
    component qual_check = GreaterEqThan(8);
    qual_check.in[0] <== qual;
    qual_check.in[1] <== min_qual;

    signal is_high_qual <== qual_check.out;
    count <== is_high_qual * (1 - in_primer);
}

template ViralConsensus(L, NUM_READS) {
    // Inputs
    signal input min_qual;
    signal input min_depth;
    signal input min_freq;
    signal input ambig;
    signal input primer_regions[L];  // 1=primer region at position
    signal input bases[NUM_READS][L];
    signal input quals[NUM_READS][L];
    signal input is_reverse[NUM_READS]; // is_reverse flag per read

    // Outputs
    signal output consensus[L];    // Signals
    signal total_depth[L];
    signal best_base[L];
    signal best_count[L];
    signal depth_ok[L];
    signal freq_ok[L];
    signal has_pass[L];
    signal is_pass[L];
    signal counts[5][L];             // counts for each base (A,C,G,T,N) per position
    signal match_counts[NUM_READS][L][5];  // temporary counts per read/pos/base    signal is_better[L][4];         // comparison results for each position and base

    // Components
    component eq[NUM_READS][L][5];      // base equality checks
    component processors[NUM_READS][L]; // base processors per read/pos
    component gt[L][4];                 // GreaterThan comparators for bases 1..4 vs best
    component depth_cmp[L];             // GreaterEqThan for min_depth check
    component freq_cmp[L];              // GreaterEqThan for min_freq check
    component is_better[L][4];           // For comparing base counts
    
    // Intermediate signals for tracking best base and count
    signal best_count_int[L][5];
    signal best_base_int[L][5];
    
    // Consensus calculation signals
    signal pass_value[L];
    signal fail_value[L];
    signal one_minus_is_pass[L];
    signal pass_term[L];
    signal fail_term[L];
    
    // Initialize all components in the initial scope
    for (var pos = 0; pos < L; pos++) {
        // Initialize depth and frequency comparators
        depth_cmp[pos] = GreaterEqThan(32);  // 32-bit comparison for depth
        freq_cmp[pos] = GreaterEqThan(32);   // 32-bit comparison for frequency
        
        // Initialize base comparison components
        for (var b = 0; b < 4; b++) {
            is_better[pos][b] = GreaterThan(32);
        }
    }
    
    // Instantiate eq components and connect inputs
    for (var r = 0; r < NUM_READS; r++) {
        for (var pos = 0; pos < L; pos++) {
            for (var base = 0; base < 5; base++) {
                eq[r][pos][base] = IsEqual();
                eq[r][pos][base].in[0] <== bases[r][pos];
                eq[r][pos][base].in[1] <== base;
            }
        }
    }

    // Instantiate BaseProcessors and compute match_counts
    for (var r = 0; r < NUM_READS; r++) {
        for (var pos = 0; pos < L; pos++) {
            processors[r][pos] = BaseProcessor();
            processors[r][pos].min_qual <== min_qual;
            processors[r][pos].base <== bases[r][pos];
            processors[r][pos].qual <== quals[r][pos];
            processors[r][pos].ref_pos <== pos;
            processors[r][pos].is_reverse <== is_reverse[r];
            processors[r][pos].in_primer <== primer_regions[pos];

            for (var base = 0; base < 5; base++) {
                // 1 if base matches and count allowed, else 0
                match_counts[r][pos][base] <== eq[r][pos][base].out * processors[r][pos].count;
            }
        }
    }    // Sum match_counts over reads to get counts per base and position
    for (var base = 0; base < 5; base++) {
        for (var pos = 0; pos < L; pos++) {
            var sum = 0;
            for (var r = 0; r < NUM_READS; r++) {
                sum += match_counts[r][pos][base];
            }
            counts[base][pos] <== sum;
        }
    }    // Calculate consensus per position
    for (var pos = 0; pos < L; pos++) {
        // total_depth = sum of counts of all bases
        total_depth[pos] <== counts[0][pos] + counts[1][pos] + counts[2][pos] + counts[3][pos] + counts[4][pos];

        // Initialize with first base
        best_count_int[pos][0] <-- counts[0][pos];
        best_base_int[pos][0] <-- 0;
        
        // Compare with other bases and update best
        for (var b = 1; b < 5; b++) {
            // Compare current base with previous best
            is_better[pos][b-1].in[0] <== counts[b][pos];
            is_better[pos][b-1].in[1] <== best_count_int[pos][b-1];
            
            // Update best count (max of current best and this base)
            best_count_int[pos][b] <-- is_better[pos][b-1].out * counts[b][pos] + 
                                    (1 - is_better[pos][b-1].out) * best_count_int[pos][b-1];
            
            // Update best base if this base is better
            best_base_int[pos][b] <-- is_better[pos][b-1].out * b + 
                                   (1 - is_better[pos][b-1].out) * best_base_int[pos][b-1];
        }
        
        // Final assignment to output signals
        best_count[pos] <== best_count_int[pos][4];
        best_base[pos] <== best_base_int[pos][4];

        // Depth threshold check
        // Components already instantiated in initial scope
        depth_cmp[pos].in[0] <== best_count[pos];
        depth_cmp[pos].in[1] <== min_depth;
        depth_ok[pos] <== depth_cmp[pos].out;

        // Frequency threshold check: best_count*100 >= total_depth*min_freq
        freq_cmp[pos].in[0] <== best_count[pos] * 100;
        freq_cmp[pos].in[1] <== total_depth[pos] * min_freq;
        freq_ok[pos] <== freq_cmp[pos].out;

        has_pass[pos] <== depth_ok[pos] * freq_ok[pos];
        is_pass[pos] <== has_pass[pos];

        // Calculate consensus using quadratic constraints
        pass_value[pos] <-- best_base[pos];
        fail_value[pos] <-- ambig;
        
        // Break down the calculation into quadratic steps
        one_minus_is_pass[pos] <-- 1 - is_pass[pos];
        
        // Calculate terms separately
        pass_term[pos] <-- is_pass[pos] * pass_value[pos];
        fail_term[pos] <-- one_minus_is_pass[pos] * fail_value[pos];
        
        // Final sum
        consensus[pos] <-- pass_term[pos] + fail_term[pos];
        
        // Add constraint to ensure consistency
        pass_term[pos] + fail_term[pos] === consensus[pos];
    }
}

component main = ViralConsensus(100, 50);
