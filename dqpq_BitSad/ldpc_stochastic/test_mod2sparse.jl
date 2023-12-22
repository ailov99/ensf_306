using SparseArrays

include("mod2sparse.jl")


H = sparse([1, 1, 2, 2, 3, 3, 4, 4], [1, 2, 2, 3, 4, 5, 5, 6], [11, 22, 33, 44, 55, 66, 77, 88])
# 11  22   ⋅   ⋅   ⋅   ⋅
#  ⋅  33  44   ⋅   ⋅   ⋅
#  ⋅   ⋅   ⋅  55  66   ⋅
#  ⋅   ⋅   ⋅   ⋅  77  88

@assert(mod2sparse_first_in_row(H, 1) == 1)
@assert(mod2sparse_first_in_row(H, 2) == 3)
@assert(mod2sparse_first_in_row(H, 3) == 5)
@assert(mod2sparse_first_in_row(H, 4) == 7)

@assert(mod2sparse_last_in_row(H, 1) == 2)
@assert(mod2sparse_last_in_row(H, 2) == 4)
@assert(mod2sparse_last_in_row(H, 3) == 6)
@assert(mod2sparse_last_in_row(H, 4) == 8)

@assert(mod2sparse_at_end_col(H, 1, 11) == true)
@assert(mod2sparse_at_end_col(H, 2, 33) == true)
@assert(mod2sparse_at_end_col(H, 3, 44) == true)
@assert(mod2sparse_at_end_col(H, 4, 55) == true)
@assert(mod2sparse_at_end_col(H, 5, 77) == true)
@assert(mod2sparse_at_end_col(H, 6, 77) == false)


print("done")