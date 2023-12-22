module Codes
export get_hgp_pcm

using SparseArrays
using PyCall

function __init__()
    py"""
    import numpy as np
    from ldpc.codes import rep_code
    from bposd.hgp import hgp
    
    def get_pcm(d=5):
        h = rep_code(d)
        surface_code = hgp(h1=h, h2=h, compute_distance=True)
        return surface_code.hz   
    """
end

function get_hgp_pcm(d::Integer)::SparseMatrixCSC{Int8, Int64}
    jl_arr = py"get_pcm"(d)
   
    rows,cols = size(jl_arr)
    H = spzeros(Int8, rows, cols)

    for i = 1:rows
        for j = 1:cols
            H[i,j] = jl_arr[i,j]
        end
    end

    return H
end

# TODO: Translate to Julia
#function hamming_code(rank)
#    """
#    Outputs a Hamming code parity check matrix given its rank.
#    
#    Parameters
#    ----------
#    rank: int
#        The rank of of the Hamming code parity check matrix.
#
#    Returns
#    -------
#    numpy.ndarray
#        The Hamming code parity check matrix in numpy.ndarray format. 
#
#    
#    Example
#    -------
#    >>> print(hamming_code(3))
#    [[0 0 0 1 1 1 1]
#     [0 1 1 0 0 1 1]
#     [1 0 1 0 1 0 1]]
#
#    """
#    rank = int(rank)
#    num_rows = (2 ^ rank) - 1
#
#    pc_matrix = np.zeros((num_rows, rank), dtype=int)
#
#    for i in range(0, num_rows):
#        pc_matrix[i] = mod10_to_mod2(i + 1, rank)
#
#    return pc_matrix.T
#end

# TODO: Translate to Julia
#function ring_code(distance)
#    """
#    Outputs ring code (closed-loop repetion code) parity check matrix
#    for a specified distance. 
#
#    Parameters
#    ----------
#    distance: int
#        The distance of the repetition code.
#
#    Returns
#    -------
#    numpy.ndarray
#        The repetition code parity check matrix in numpy.ndarray format.
#
#    Examples
#    --------
#    >>> print(ring_code(5))
#    [[1 1 0 0 0]
#     [0 1 1 0 0]
#     [0 0 1 1 0]
#     [0 0 0 1 1]
#     [1 0 0 0 1]]
#    """
#
#    pcm = np.zeros((distance, distance), dtype=int)
#
#    for i in range(distance - 1):
#        pcm[i, i] = 1
#        pcm[i, i + 1] = 1
#
#    # close the loop
#    i = distance - 1
#    pcm[i, 0] = 1
#    pcm[i, i] = 1
#
#    return pcm
#end

end