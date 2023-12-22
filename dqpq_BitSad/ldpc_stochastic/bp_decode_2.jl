#SBitStream values: channel probabilities, check_to_bit values, bit_to_check values,

#Need to store bit_to_check and check_to_bit for each entry in the sparse matrix
# Possible options:
#   1. Two parallel sparse matrices, one for bit_to_check and one for check_to_bit.
#   2. Two arrays parallel with m.nzval of bit_to_check messages and check_to_bit messages.
# A: Currently going with option 2, called bits_to_checks and checks_to_bits respectively.

using BitSAD
using SparseArrays

include("mod2sparse.jl")

export decoder, bp_decode_prob_ratios

mutable struct decoder
    # a list of SBitstream[] to store the channel probabilities
    channel_probs
    # a parity check matrix stored as a sparse array
    # it is used for extracting where and how messages are passed
    H
    # maximum number of BP iterations -- the depth of the circuit
    max_iter
    # the syndrome to compare against the convergence of BP -- stored as string
    synd
    # not used for the moment -- uses a list of SBitstream[]
    log_prob_ratios 
    # no clue 
    bp_decoding
    # the actual solution, the vector of soft decisions
    bp_decoding_synd
    # the first dimension of H
    N
    # the second dimension of H
    M
    # a flag to determine if the second decoding stage (e.g. OSD) should be used or not
    converge
    # message passing arrays of SBitStreams
    bits_to_checks
    checks_to_bits
end

# Product Sum implementation of BP
function bp_decode_prob_ratios(dec)
    for j in 1:dec.N
        # e_index is the index of the first non-zero entry in column j of H.
        e_index = mod2sparse_first_in_col(dec.H, j)
        while !(mod2sparse_at_end_col(dec.H, j, e_index))
            # print("index ", e_index, "\n")
            dec.bits_to_checks[e_index] = SBitstream(float(dec.channel_probs[j]) / (1.0 - float(dec.channel_probs[j]))) #first
            e_index = mod2sparse_next_in_col(e_index)
        end
    end

    dec.converge = 0

    #TODO: change this to go by columns rather than by rows, Julia is column-major.
    for iteration in 1:(dec.max_iter+1)
        if iteration > dec.max_iter+1
            println("Iteration is $iteration")
        end
        for i in 1:dec.M
            e = mod2sparse_first_in_row(dec.H, i)
            temp = SBitstream((-1.0) ^(float(dec.synd[i])))
            while !(mod2sparse_at_end_row(dec.H, i, e))
                #print(" first loop ")
                dec.checks_to_bits[e] = temp #first
                temp = temp * SBitstream(2.0/(1.0 + float(dec.bits_to_checks[e])) - 1)
                e = mod2sparse_next_in_row(dec.H, e)
            end
            
            e = mod2sparse_last_in_row(dec.H, i)
            temp = SBitstream(1.0)
            while !(mod2sparse_at_start_row(dec.H, i, e))
                #print("second loop, e is ", e, "\n")
                dec.checks_to_bits[e] = dec.checks_to_bits[e] * temp
                dec.checks_to_bits[e] = SBitstream((1.0 - float(dec.checks_to_bits[e])) / (1.0 + float(dec.checks_to_bits[e])))
                temp = temp * SBitstream(2.0 / (1.0 + float(dec.bits_to_checks[e])) - 1.0)
                e = mod2sparse_prev_in_row(dec.H, e)
            end
        end
        # #bit to check messages
        for j in 1:dec.N
            e = mod2sparse_first_in_col(dec.H, j)
            temp = SBitstream(float(dec.channel_probs[j]) / (1.0 - float(dec.channel_probs[j])))
            while !(mod2sparse_at_end_col(dec.H, j, e))
                #print(2)
                dec.bits_to_checks[e] = temp
                temp = temp * dec.checks_to_bits[e]
                #Maybe an isnan(temp) check here? idk when that would be true though. bp_decoder.pyx line 287
                e = mod2sparse_next_in_col(e)
            end
            #dec.log_prob_ratios[j] = temp
            #TODO: How? Should this not be <= 1?
            if float(temp) >= 1 
                dec.bp_decoding[j] = 1
            else
                dec.bp_decoding[j] = 0
            end

            e = mod2sparse_last_in_col(dec.H, j)
            temp = SBitstream(1.0)
            while !(mod2sparse_at_start_col(dec.H, j, e))
                #print(1)
                dec.bits_to_checks[e] = dec.bits_to_checks[e] * temp
                temp = temp * dec.checks_to_bits[e]
                #maybe nan check on temp again?
                e = mod2sparse_prev_in_col(e)
            end

            # #no SBitstreams!!
            mod2sparse_mulvec(dec.H, dec.bp_decoding, dec.bp_decoding_synd) 

            # There should be a way for the iterations to end sooner
            dec.converge = true
            old_iter = iteration
            iteration = dec.max_iter+2
            #
            # The circuit can be exited sooner, and we need a way to ensure that the result
            # of mod2sparse_mulvec is analysed (thresholded) and compared in the 
            # if statement inside the following for-loop
            #
            for check in 1:dec.M
                if parse(Int, dec.synd[check]) != dec.bp_decoding_synd[check]
                    println("Setting iteration to old_iter")
                    dec.converge = false
                    iteration = old_iter
                    break
                end
            end
        end
    end
end