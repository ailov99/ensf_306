#This is a new version of the necessary mod2sparse functions for decoding which makes use
# of the sparsearrays library in julia.

# The original methods are the following
#define mod2sparse_first_in_row(m,i) ((m)->rows[i].right) /* Find the first   */
#define mod2sparse_first_in_col(m,j) ((m)->cols[j].down)  /* or last entry in */
#define mod2sparse_last_in_row(m,i) ((m)->rows[i].left)   /* a row or column  */
#define mod2sparse_last_in_col(m,j) ((m)->cols[j].up)

#define mod2sparse_next_in_row(e) ((e)->right)  /* Move from one entry to     */
#define mod2sparse_next_in_col(e) ((e)->down)   /* another in any of the four */
#define mod2sparse_prev_in_row(e) ((e)->left)   /* possible directions        */
#define mod2sparse_prev_in_col(e) ((e)->up)   

#define mod2sparse_at_end(e) ((e)->row<0) /* See if we've reached the end     */

#define mod2sparse_row(e) ((e)->row)      /* Find out the row or column index */
#define mod2sparse_col(e) ((e)->col)      /* of an entry (indexes start at 0) */

#define mod2sparse_rows(m) ((m)->n_rows)  /* Get the number of rows or columns*/
#define mod2sparse_cols(m) ((m)->n_cols)  /* in a matrix                      */


#Need to get first and last non-zero element in each row/col of a sparse matrix
#these are redundant. Access bit_to_check for an entry at the index of that entry in nzval.
#and same for check_to_bit, as these are 3 parallel arrays.

# the entry is only the value that one is searching for.
# in the original radford neal code the entry was a struct that contained
# pointers to the neighbours, it had row and col information
# as well as the associated value

function mod2sparse_at_start_row(m, row, e_index)
    return (mod2sparse_first_in_row(m, row) == e_index)
end

#unfortunately requires m as well as e, not as elegant as next_in_col
function mod2sparse_next_in_row(m, e_index)
    row = m.rowval[e_index]
    for i in (e_index + 1):length(m.rowval)
        if (m.rowval[i] == row)
            return i
        end
    end
end

#can only guarantee a prev exists with a unique mod2sparse_at_start_row function
function mod2sparse_prev_in_row(m, e)
    for i in (e-1):-1:1
        if (m.rowval[i] == m.rowval[e])
            return i
        end
    end
end

#TODO:
#structs, SBitStreams


# each entry in the sparse matrix corresponds to a pair formed of colptr and rowval
# where len(matrix.colptr) == len(matrix.rowval)
# each entry in the sparse matrix has an entry-index:
#   * runs from 1:len(matrix.rowval)
#   * which is the same in the colptr and rowval lists of the sparse array
# The documentation about sparse matrices is https://docs.julialang.org/en/v1/stdlib/SparseArrays/#man-csc


#Note: m.colptr is always of size n+1 for a matrix of n non-zero elements.
#Q: How should this function behave in the absence of a non-zero element in the column?
#A: For now, assume this is never the case. TODO: ACTUALLY ANSWER THIS LATER
#returns the index of the value in nzval associated with the first non-zero element of column i in sparse matrix m.
function mod2sparse_first_in_col(m, col)
    e_index = m.colptr[col]
    return e_index
end

#No index out of bounds error because colptr is 1 too large.
function mod2sparse_last_in_col(m, col) 
    e_index = m.colptr[col+1] - 1
    return e_index
end

#returns true if value is the last nz element in the column of m, false otherwise.
#TODO: make this such that m does not need to be passed as a parameter.
#I am unsure if I need separate at_end row and col functions.
function mod2sparse_at_end_col(m, col, e_index)
    if col + 1 > length(m.colptr)
        return true
    end
    # return (m.nzval[m.colptr[col+1] - 1] == value)
    return m.colptr[col+1] - 1 == e_index
end

#this sucks. TODO: is there a way to not use m?
function mod2sparse_at_end_row(m, row, e_index)
    return (mod2sparse_last_in_row(m, row) == e_index)
end

#returns the nzval index associated with the next nz value in a matrix.
#TODO: get rid of this function call, only kept for now to mirror original structure.
function mod2sparse_next_in_col(e_index)
    return e_index + 1
end

#SHOULD TRY TO ACCESS BY COLUMN, NOT ROW.
#Q: How should this function behave in the absence of a non-zero element in the column?
#A: For now, assume this is never the case. TODO: ACTUALLY ANSWER THIS LATER
#returns the index of the value in nzval associated with the first non-zero element of row i in sparse matrix m.
function mod2sparse_first_in_row(m, row) #m is assumed to be a SparseMatrixCSC struct
    for e_index in 1:length(m.rowval) #(front to back)
        if (m.rowval[e_index] == row)
            # print("row:", row, " first:", e_index, "\n")
            return e_index
        end
    end
    return -1
end

function mod2sparse_last_in_row(m, row)
    for e_index in length(m.rowval):-1:1 #(back to front)
        if (m.rowval[e_index] == row)
            return e_index
        end
    end
end

function mod2sparse_at_start_col(m, col, e_index)
    return (e_index >= m.colptr[col])
end

function mod2sparse_prev_in_col(e_index)
    return e_index - 1
end

function mod2sparse_bit_to_check(bits_to_checks, e_index)
    return bits_to_checks[e_index]
end

function mod2sparse_check_to_bit(checks_to_bits, e_index)
    return checks_to_bits[e_index]
end

function mod2sparse_mulvec(H, received_codeword, synd)
    nr_rows = size(H)[1]
    nr_cols = size(H)[2]

    for i in 1:nr_rows
        synd[i] = 0
    end

    for j in 1:nr_cols
        if received_codeword[j] == 1
            e_index = mod2sparse_first_in_col(H, j)
            while !(mod2sparse_at_end_col(H, j, e_index))
                # synd[H.rowval[e_index]] ^= 1
                synd[H.rowval[e_index]] ⊻= 1
                e_index = mod2sparse_next_in_col(e_index)
            end
        end
    end
end