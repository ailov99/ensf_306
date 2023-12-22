using BitSAD
using TimerOutputs

include("bp_decode_2.jl")
include("codes.jl")
using .Codes

global use_old_dummy_matrix = false
global do_sim = false

function create_sample_decoder(dist)
    if use_old_dummy_matrix
        # 11  22   ⋅   ⋅   ⋅   ⋅
        #  ⋅  33  44   ⋅   ⋅   ⋅
        #  ⋅   ⋅   ⋅  55  66   ⋅
        #  ⋅   ⋅   ⋅   ⋅  77  88
        H = spzeros(Int8, 4, 6)
        H[1,1] = 11
        H[1,2] = 22
        H[2,2] = 33
        H[2,3] = 44
        H[3,4] = 55
        H[3,5] = 66
        H[4,5] = 77
        H[4,6] = 88
    else
        H = Codes.get_hgp_pcm(dist)
    end

    M, N = size(H)
    println("Distance $dist dims $M x $N")

    max_iter = 1
    #inputvector as string

    if use_old_dummy_matrix
        synd = "0010"
    else
        synd_list = ["0" for i = 1:M]
        #synd_list[M-1] = "1" # Causes saturation?
        synd = join(synd_list)
    end

    #should this be an SBitstream?
    log_prob_ratios = [] 
    bp_decoding = []
    bp_decoding_synd = []
    

    x1 = SBitstream(0.05)
    zero = SBitstream(0.0)

    converge = false
    channel_probs = []
    bits_to_checks = []
    checks_to_bits = []

    # In the original mod2sparse there are two double values per entry
    for i in 1:length(H.nzval)
        push!(bits_to_checks, zero)
        push!(checks_to_bits, zero)
    end

    for i in 1:N
        push!(channel_probs, x1)
        push!(bp_decoding, 0)
        push!(log_prob_ratios, zero)
    end

    for i in 1:M
        push!(bp_decoding_synd, 0)
    end


    sampleDec = decoder(
        channel_probs, 
        H, 
        max_iter, 
        synd, 
        log_prob_ratios, 
        bp_decoding, 
        bp_decoding_synd,
        N, 
        M, 
        converge, 
        bits_to_checks, 
        checks_to_bits
    )

    return sampleDec
end

if !do_sim
    # ============= HDL gen ================
    # lates -> without bookmarks -> original
    # --------------------------------------
    # 3 (6x13) (16145): 
    # 641.984 ms (3163111 allocations: 125.84 MiB
    # 1.270 s (3163084 allocations: 125.84 MiB)
    # 434.694836 s (4.62 G allocations: 97.815 GiB)
    # --------------------------------------
    # 5: (20x41) (146689)
    # 7.338 s (31759388 allocations: 1.26 GiB)
    # 278.321 s (31759369 allocations: 1.26 GiB)
    #  > 1 hr
    # --------------------------------------
    # 10 (90x181) (2831489):
    # 126.237 s (772502014 allocations: 31.59 GiB)
    # > 1 hr
    # > 1 hr
    # --------------------------------------
    # 15 (210x421) (15447089):
    # 892.954 s (5588315077 allocations: 234.20 GiB)
    # > 1 hr
    # > 1 hr
    # --------------------------------------
    # 20: (380x761) (50785489):
    # > 1 hr
    # > 1 hr
    # > 1 hr
    # --------------------------------------
    println("..... compiling Verilog ....")
    sampleDec = create_sample_decoder(3)
    using BenchmarkTools
    @time generatehw(bp_decode_prob_ratios, sampleDec)
    f_verilog, f_circuit = generatehw(bp_decode_prob_ratios, sampleDec)
    io = open("hwfile.vl", "w")
    write(io, f_verilog)
    close(io)
end

if do_sim
    # ============== Sim =================== 
    sampleDec = create_sample_decoder(5)
    a = bp_decode_prob_ratios(sampleDec)
    a_bits_to_checks = copy(sampleDec.bits_to_checks)
    a_checks_to_bits = copy(sampleDec.checks_to_bits)
    est_bits_to_checks = Array{Float64}(undef, length(a_bits_to_checks))
    est_checks_to_bits = Array{Float64}(undef, length(a_checks_to_bits))

    hsim = simulatable(bp_decode_prob_ratios, sampleDec)

    num_samples = 1000
    for i in 1:num_samples
        println("At iteration $i")

        # Re-create decoder at each sample OR re-use converged
        newSampleDec = sampleDec
        #newSampleDec = create_sample_decoder()
        hsim(bp_decode_prob_ratios, newSampleDec)

        for j in eachindex(a_bits_to_checks)
            push!(a_bits_to_checks[j], pop!(newSampleDec.bits_to_checks[j]))
        end
        for j in eachindex(a_checks_to_bits)
            push!(a_checks_to_bits[j], pop!(newSampleDec.checks_to_bits[j]))
        end
    end

    for j in eachindex(a_bits_to_checks)
        est_bits_to_checks[j] = abs(estimate(a_bits_to_checks[j]) - float(a_bits_to_checks[j]))
    end
    for j in eachindex(a_checks_to_bits)
        est_checks_to_bits[j] = abs(estimate(a_checks_to_bits[j]) - float(a_checks_to_bits[j]))
    end
    @show est_bits_to_checks
    @show est_checks_to_bits
end
# ======================================
println("...done")


#tmr = TimerOutput()
## Run stats:
## dist 3  = 6 x 13           = 16145 tape    =
## dist 4  = 12 x 25          = 55889 tape    =
## dist 5  =  20 x 41  matrix = 146689 tape   = 1985s-> 360s -> 7.46s
## dist 10 =  90 x 181 matrix = 2831489 tape  =         ...s -> 166s
## dist 20 = 380 x 761 matrix = 50785489 tape = ...
#distances = [3]
#
#for i in distances
#    main(tmr, i,true)
#end 
#show(tmr)
#
#reset_timer!(tmr)