using TimerOutputs

tmr = TimerOutput()

USE_TMR = true

const stdcomment = "// Autogenerated by BitSAD"

propagate_constant(sig...) = false
propagate_constant(::typeof(size), args...) = true
propagate_constant(::typeof(length), x) = true

"""
    gethandler(isbroadcast::Bool, ftype::Type, argtypes::Type...)

Return an instance of the hardware handler for the call of type `ftype`
on arguments of types `argtypes`.
`isbroadcast` is true if the call is a broadcasted call.

Custom operators should overload this function to generate SystemVerilog
for calls to the operator.

See also [`BitSAD.init_state`](#).
"""
function gethandler end

"""
    init_state(handler)

Initialize the state for `handler`.
This can be used to maintain information across multiple calls to `handler`.

See also [`BitSAD.gethandler`](#).
"""

is_hardware_primitive(sig...) = is_trace_primitive(sig...)

"""
    generatehw([io::IO = IOBuffer()], f, args...;
               top = nameof(f), submodules = [],
               transforms = [insertrng!, constantreduction!])

Generate a SystemVerilog module named `top` for `f(args...)` as a circuit.
Apply `transforms` to the circuit before generating the SystemVerilog.
"""
function generatehw(io::IO, f, args...;
                    top = _nameof(f),
                    submodules = [],
                    transforms = [insertrng!, constantreduction!])

    println("__FROM__LIB__CODE__")
    # get tape and transform
    # if f itself is a primitive, do a manual tape
    if is_hardware_primitive(Ghost.get_type_parameters(Ghost.call_signature(f, args...))...)
        tape = Ghost.Tape()
        inputs = Ghost.inputs!(tape, f, args...)
        if _isstruct(f)
            tape.result = push!(tape, Ghost.mkcall(inputs...))
        else
            tape.result = push!(tape, Ghost.mkcall(f, inputs[2:end]...))
        end
    else
        println("Tracing_into_tape...")
        if USE_TMR
            @timeit tmr "1_tape_trace" tape = trace(f, args...; isprimitive = is_hardware_primitive, submodules = submodules)
        else
            tape = trace(f, args...; isprimitive = is_hardware_primitive, submodules = submodules)
        end
    end

    if USE_TMR
        tape_len = length(tape)
        println("Tape length: $tape_len")
        @timeit tmr "2_tform_unbroadcast" transform!(_unbroadcast, tape)
        @timeit tmr "3_tform_squash_bin_vararg" transform!(_squash_binary_vararg, tape)
        @timeit tmr "4_tape_ctor" tape = Ghost.Tape(tape.ops, tape.result, tape.parent, tape.meta, TupleCtx())
        @timeit tmr "5_tform_record_ts_and_ss" transform!(_record_tuples_and_splats, tape)
        @timeit tmr "6_tform_reroute_tuple_index" transform!(_reroute_tuple_index, tape)
        @timeit tmr "7_tform_desplat" transform!(_desplat, tape)
        # transform!(_squash_tuple_index, tape) # Note: This was commented out in the original code

        # extract tape into module
        @timeit tmr "8_circuit_module_ctor" m = CircuitModule(fn = f, name = top)
        #buildBookmarks!(tape.ops, 1_000)
        @timeit tmr "9_extracttrace" extracttrace!(m, tape)
        #invalidateBookmarks!(tape.ops) # Not needed as long as tape = nothing after
        show(tape)
        tape = nothing # don't hold onto tape

        # apply transformations
        @timeit tmr "10_foreach_tforms" foreach(t! -> t!(m), transforms)

        # replace constants with Verilog strings
        @timeit tmr "11_veri_str_replace" constantreplacement!(m)

        # generate verilog string
        @timeit tmr "12_veri_str_gen" generateverilog(io, m)

        #show(tmr)
    else
        transform!(_unbroadcast, tape)
        transform!(_squash_binary_vararg, tape)
        tape = Ghost.Tape(tape.ops, tape.result, tape.parent, tape.meta, TupleCtx())
        transform!(_record_tuples_and_splats, tape)
        transform!(_reroute_tuple_index, tape)
        transform!(_desplat, tape)
        # transform!(_squash_tuple_index, tape) # Note: This was commented out in the original code

        # extract tape into module
        m = CircuitModule(fn = f, name = top)
        extracttrace!(m, tape)
        tape = nothing # don't hold onto tape

        # apply transformations
        foreach(t! -> t!(m), transforms)

        # replace constants with Verilog strings
        constantreplacement!(m)

        # generate verilog string
        generateverilog(io, m)
    end

    return io, m
end
function generatehw(f, args...; kwargs...)
    buffer = IOBuffer()
    buffer, m = generatehw(buffer, f, args...; kwargs...)

    return String(take!(buffer)), m
end

_getstructname(::T) where T = lowercase(string(nameof(T)))

_handle_parameter(parameter::Number, submodules) = parameter
_handle_parameter(parameter::AbstractArray{<:Number}, submodules) = parameter
_handle_parameter(parameter::Tuple, submodules) = map(parameter) do p
    _handle_parameter(p, submodules)
end
function _handle_parameter(::T, submodules) where T
    (T ∈ submodules) || @warn "Parameter of type $T will be ignored (cannot encode in Verilog)"

    return nothing
end

function _handle_getproperty!(m::CircuitModule, call, param_map, const_map)
    # if we are getting a property from the top level function
    # then treat this as a parameter
    if m.fn == _gettapeval(call.args[1])
        # get the value of the parameter, handling tuples accordingly
        val = _handle_parameter(_gettapeval(call), m.submodules)
        # get the name of the parameter as the symbol of the property
        prop = string(_gettapeval(call.args[2]))
        # _handle_parameter returns nothing for parameters
        # that cannot be encoded in SystemVerilog
        encodable = (val isa Tuple) ? !all(isnothing, val) : !isnothing(val)
        if encodable
            # if the parameter is encodable,
            # store it in the CircuitModule for later
            # also store is in the param_map so we can replace
            # references in the call stack with the symbol
            m.parameters[prop] = val
            param_map[_getid(call)] = prop
        end
    else
        # anything that isn't accessing a top level struct
        # is treated like a constant in the circuit
        # these constants may or may not be valid SystemVerilog
        const_map[_getid(call)] = string(_gettapeval(call))
    end

    return m
end

# recurse calls to Base.materialize until we get the function
# being broadcasted
# our tracing will eagerly materialize
function _get_materialize_origin(x)
    origin = _gettapeop(x)

    return (origin.fn == Base.materialize) ? _get_materialize_origin(origin.args[1]) : x
end

function extracttrace!(m::CircuitModule, tape::Ghost.Tape)
    println("_____IN________EXTRACT____________")
    # we use ids instead of Ghost.Variables as keys b/c
    # there are hashing issues with Ghost.Variable
    # see https://github.com/dfdx/Ghost.jl/issues/20
    param_map = Dict{Int, String}()
    const_map = Dict{Int, String}()
    materialize_map = Dict{Int, Tuple{Ghost.Variable, Any}}()
    # skip first call which is the function being compiled
    non_skip_counter = 0
    for call in tape
        if call isa Ghost.Call
            # get the function representing this entry in the tape
            # if it is a Constant, use the underlying value
            # otherwise it is just the Julia function/callable stored in the entry
            @timeit tmr "extract_gettapeval" fn = (_gettapeval(call.fn) isa Ghost.Constant) ? _gettapeval(call.fn).val : call.fn

            # ignore materialize calls
            @timeit tmr "extract_materialize_call" begin
            if fn == Base.materialize
                origin = _get_materialize_origin(call.args[1])
                # store the "origin" of the broadcasting so that we can
                # reference back to it
                materialize_map[_getid(call)] = (origin, _gettapeval(call))
                continue
            end
            end

            # handle calls to getproperty
            # in particular, calling get property on the top level
            # will be treated as a parameter
            @timeit tmr "extract_get_prop" begin
            if fn == Base.getproperty
                _handle_getproperty!(m, call, param_map, const_map)
                continue
            end
            end

            # if this call should be treated like a propagated constant then propagate it!
            @timeit tmr "extract_propagate_const_block" begin
            if propagate_constant(fn, _gettapeval.(call.args))
                const_map[_getid(call)] = string(_gettapeval(call))
            elseif all(arg -> haskey(const_map, _getid(arg)), call.args)
                const_map[_getid(call)] = string(_gettapeval(call))
            end
            end

            # if the current call isn't something we would generate hardware for
            # then skip it (this can result in unconnected nets in the final circuit)
            @timeit tmr "extract_is_hw_prim" begin
           # println("_EXTRACT_IS_HIW_PRIM")
            

            is_hw_prim =  is_hardware_primitive(Ghost.get_type_parameters(Ghost.call_signature(tape, call))...)
            if !is_hw_prim
                continue
            end
            non_skip_counter += 1
            end
           # println("_EXTRACT_IS_HIW_PRIM_END_")
            # create Operator for Ghost.Call (handling broadcast)
            # structs are renamed as Foo -> foo_$id
            # plain functions are name ""
            @timeit tmr "extract_name" name = _isstruct(fn) ? _getstructname(fn) * "_$(_getid(fn))" : ""
            isbroadcast = _isbcast(fn)
            @timeit tmr "extract_fn" fn = isbroadcast ? _gettapeval(call.args[1]) : fn
            @timeit tmr "extract_op_set" op = (name = Symbol(name), type = typeof(fn), broadcasted = isbroadcast)

            @timeit tmr "extract_map" begin
            # map inputs and outputs of Ghost.Call to Nets
            # set args that are Ghost.Input to :input class
            inputs = map(call.args[(1 + isbroadcast):end]) do arg
                # get the id of the argument on the call stack and its value
                # check the materialize_map first to see if this argument references
                # the output of a broadcasted operation (effectively bypassing the materialize)
                arg, val = get(materialize_map, _getid(arg), (arg, _gettapeval(arg)))
                # if the argument is a
                # - parameter: replace its name with the parameter name and class as :parameter
                # - constant: replace its name with the constant string and class as :constant
                # - a variable in the Ghost sense: generate the name "net_$id" and class :internal
                # - something else: just dump the value string and class as :constant
                name, class = haskey(param_map, _getid(arg)) ? (param_map[_getid(arg)], :parameter) :
                       haskey(const_map, _getid(arg)) ? (const_map[_getid(arg)], :constant) :
                       _isvariable(arg) ? ("net_$(_getid(arg))", :internal) :
                       (string(val), :constant)
                net = Net(val; name = name, class = class)

                return net
            end
            end
            # get the output which is potentially broadcasted (eagerly materialize)
            @timeit tmr "extract_outval" outval = isbroadcast ? Base.materialize(_gettapeval(call)) : _gettapeval(call)
            # the output name is definitely an internal net
            # if the output is the output of the tape call stack
            # make its class :output
            @timeit tmr "extract_outclass" outclass = (tape.result == Ghost.Variable(call)) ? :output : :internal
            @timeit tmr "extract_net_ctor" output = Net(outval; name = "net_$(_getid(call))", class = outclass)

            @timeit tmr "extract_addnode" addnode!(m, inputs, [output], op)
        end
    end
    println("Non-skips: $non_skip_counter")
    return m
end
