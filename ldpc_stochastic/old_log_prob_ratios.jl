#IN PROGRESS:
#=
function bp_decode_log_prob_ratios(dec) #product-sum
    for j in 1:dec.N
        # e is first non-zero entry in column j of H.
        e = mod2sparse_first_in_col(dec.H, j)
        while !(mod2sparse_at_end_col(m, j, e))
            dec.bits_to_checks[e] = log((1 - dec.channel_probs[j]) / (dec.channel_probs[j]))
            e = mod2sparse_next_in_col(e)
        end

    dec.converge = 0
    #TODO: change this to go by columns rather than by rows, Julia is column-major.
    for iteration in 1:(dec.max_iter+1)
        for i in 1:dec.M
            e = mod2sparse_first_in_row(dec.H, i)
            temp = 1.0
            while !(mod2sparse_at_end_row(dec.H, i, e)
                checks_to_bits[e] = temp #first
                temp *= tanh(bits_to_checks[e] / 2)
                e = mod2sparse_next_in_row(dec.H, e)
            end
            e = mod2sparse_last_in_row(m, i)
            temp = 1.0
            while !(mod2sparse_at_start_row(dec.H, i, e)
                checks_to_bits[e] *= temp
                checks_to_bits[e] = (((-1)^dec.synd[i]) * log((1 + checks_to_bits[e]) / (1 - checks_to_bits[e])))
                temp *= tanh(bits_to_checks[e] / 2)
                e = mod2sparse_prev_in_row(dec.H, e)
            end

        #bit to check messages
        for j in 1:dec.N
            e = mod2sparse_first_in_col(dec.H, j)
            temp = log((1-dec.channel_probs[j]) / (dec.channel_probs[j]))
            while !(mod2sparse_at_end_col(dec.H, j, e)
                bits_to_checks[e] = temp
                temp += checks_to_bits[e]
                e = mod2sparse_next_in_col(e)
            end
            dec.log_prob_ratios[j] = temp
            if temp <= 0
                dec.bp_decoding[j] = 1
            else
                dec.bp_decoding[j] = 0

            e = mod2sparse_last_in_col(dec.H, j)
            temp = 0.0
            while !(mod2sparse_at_start_col)
                bits_to_checks[e] += temp
                temp += checks_to_bits[e]
                e = mod2sparse_prev_in_col(e)
            end

            mod2sparse_mulvec(dec.H, dec.bp_decoding, dec.bp_decoding_synd)

            equal = 1
            for check in 1:dec.M
                if dec.synd[check] != dec.bp_decoding_synd[check]
                    equal = 0
                    break
                end
            end
            if equal == 1
                dec.converge = 1
                return 1
            end

            return 0
end
=#