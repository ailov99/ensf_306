using LinearAlgebra
using OrderedCollections
using IRTools

using TimerOutputs
global tmr = nothing

function set_tmr(my_tmr)
    global tmr
    tmr = my_tmr
end

# if !@isdefined(tmr) || isnothing(tmr)
#     # if the tmr is not initialised from before
#     tmr = TimerOutput()
#     print("tmr initialised")
# else
#     print("tmr existed")
# end

include("funres.jl")
include("utils.jl")
include("tape.jl")
include("trace.jl")
include("compile.jl")