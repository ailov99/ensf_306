mutable struct ListNode{T}
    data::T
    prev::ListNode{T}
    next::ListNode{T}
    function ListNode{T}() where T
        node = new{T}()
        node.next = node
        node.prev = node
        return node
    end
    function ListNode{T}(data) where T
        node = new{T}(data)
        return node
    end
end

mutable struct MutableLinkedList{T}
    len::Int
    node::ListNode{T}
    last_access_node::ListNode{T}
    last_access_node_idx::Int
    bookmark_step::Int
    bookmarks::Vector{ListNode{T}}
    function MutableLinkedList{T}() where T
        l = new{T}()
        l.len = 0
        l.node = ListNode{T}()
        l.node.next = l.node
        l.node.prev = l.node
        l.last_access_node_idx = -1
        l.bookmarks = Vector{ListNode{T}}()
        return l
    end
end

MutableLinkedList() = MutableLinkedList{Any}()

function MutableLinkedList{T}(elts...) where T
    l = MutableLinkedList{T}()
    for elt in elts
        push!(l, elt)
    end
    return l
end

Base.iterate(l::MutableLinkedList) = l.len == 0 ? nothing : (l.node.next.data, l.node.next.next)
Base.iterate(l::MutableLinkedList, n::ListNode) = n === l.node ? nothing : (n.data, n.next)

Base.isempty(l::MutableLinkedList) = l.len == 0
Base.length(l::MutableLinkedList) = l.len
Base.collect(l::MutableLinkedList{T}) where T = T[x for x in l]
Base.eltype(::Type{<:MutableLinkedList{T}}) where T = T
Base.lastindex(l::MutableLinkedList) = l.len

function Base.first(l::MutableLinkedList)
    isempty(l) && throw(ArgumentError("List is empty"))
    return l.node.next.data
end

function Base.last(l::MutableLinkedList)
    isempty(l) && throw(ArgumentError("List is empty"))
    return l.node.prev.data
end

Base.:(==)(l1::MutableLinkedList{T}, l2::MutableLinkedList{S}) where {T,S} = false

function Base.:(==)(l1::MutableLinkedList{T}, l2::MutableLinkedList{T}) where T
    length(l1) == length(l2) || return false
    for (i, j) in zip(l1, l2)
        i == j || return false
    end
    return true
end

function Base.map(f::Base.Callable, l::MutableLinkedList{T}) where T
    if isempty(l) && f isa Function
        S = Core.Compiler.return_type(f, Tuple{T})
        return MutableLinkedList{S}()
    elseif isempty(l) && f isa Type
        return MutableLinkedList{f}()
    else
        S = typeof(f(first(l)))
        l2 = MutableLinkedList{S}()
        for h in l
            el = f(h)
            if el isa S
                push!(l2, el)
            else
                R = typejoin(S, typeof(el))
                l2 = MutableLinkedList{R}(collect(l2)...)
                push!(l2, el)
            end
        end
        return l2
    end
end

function Base.filter(f::Function, l::MutableLinkedList{T}) where T
    l2 = MutableLinkedList{T}()
    for h in l
        if f(h)
            push!(l2, h)
        end
    end
    return l2
end

function Base.reverse(l::MutableLinkedList{T}) where T
    l2 = MutableLinkedList{T}()
    for h in l
        pushfirst!(l2, h)
    end
    return l2
end

function Base.copy(l::MutableLinkedList{T}) where T
    l2 = MutableLinkedList{T}()
    for h in l
        push!(l2, h)
    end
    return l2
end

function getNodeAt(l::MutableLinkedList, idx::Int)
    @boundscheck 0 < idx <= l.len || throw(BoundsError(l, idx))

    # Accessing start or end?
    if idx == 1
        l.last_access_node = l.node.next
        l.last_access_node_idx = idx
        return l.last_access_node
    elseif idx == length(l)
        l.last_access_node = l.node.prev
        l.last_access_node_idx = idx
        return l.last_access_node
    end

    # Last accessed node adjacent?
    if l.last_access_node_idx == idx
        return l.last_access_node
    elseif l.last_access_node_idx - 1 == idx
        l.last_access_node = l.last_access_node.prev
        l.last_access_node_idx -= 1
        return l.last_access_node
    elseif l.last_access_node_idx + 1 == idx
        l.last_access_node = l.last_access_node.next
        l.last_access_node_idx += 1
        return l.last_access_node
    end

    node = l.node

    # Use bookmarks?
    if useBookmarks(l)
        div_by_step = idx/l.bookmark_step
        closest_bookmark = convert(Int64, round(div_by_step))

        node = l.bookmarks[closest_bookmark+1]
        closest_bookmark_i = 
            closest_bookmark == 0 ? 1 : 
            closest_bookmark == length(l.bookmarks)-1 ? length(l) : 
            closest_bookmark * l.bookmark_step
      
        if div_by_step >= closest_bookmark
            # rounded down
            for i = closest_bookmark_i:(idx-1)
                node = node.next
            end
        else
            # rounded up
            for i = idx:(closest_bookmark_i-1)
                node = node.prev
            end
        end

        l.last_access_node_idx = idx
        l.last_access_node = node
        return node
    end

    # Haven't accessed node or neighbours previously => scan whole list
    if idx > (l.len/2)
        for i in 1:(l.len-idx+1)
            node = node.prev
        end
    else
        for i in 1:idx
            node = node.next
        end
    end

    l.last_access_node_idx = idx
    l.last_access_node = node
    return node
end

function insertData!(l::MutableLinkedList, idx::Int, data::T...) where T
    @boundscheck 0 < idx <= l.len || throw(BoundsError(l, idx))
    local node
    if idx == 1
        node = l.node.next
    elseif idx == l.len
        node = l.node.prev
    else
        node = getNodeAt(l, idx)
    end

    new_data_len = length(data)
    for i = 1:new_data_len
        prev = node.prev
        new_node = ListNode{T}(data[i])
        new_node.next = node
        new_node.prev = prev
        prev.next = new_node
        node.prev = new_node
        l.len += 1 
    end

    return l
end

# ================== Bookmarks =================
function buildBookmarks!(l::MutableLinkedList, step::Int)
    l.bookmark_step = step
    node = l.node
    push!(l.bookmarks, l.node.next)

    for i = 1:convert(Int64, floor(l.len/step))
        for j = 1:step
            node = node.next
        end
        push!(l.bookmarks, node)
    end

    push!(l.bookmarks, l.node.prev)

    tape_size = length(l)
    bkmarks_size = length(l.bookmarks)
    println("Tape of size $tape_size = bkmarks of size $bkmarks_size")

    return l
end

function useBookmarks(l::MutableLinkedList)
    return !isempty(l.bookmarks)
end

function invalidateBookmarks!(l::MutableLinkedList{T}) where T
    l.bookmarks = Vector{ListNode{T}}()
    l.bookmark_step = -1
    return l
end
# ===============================================

function Base.getindex(l::MutableLinkedList, idx::Int)
    @boundscheck 0 < idx <= l.len || throw(BoundsError(l, idx))
    node = getNodeAt(l, idx)
    return node.data
end

function Base.getindex(l::MutableLinkedList{T}, r::UnitRange) where T
    @boundscheck 0 < first(r) < last(r) <= l.len || throw(BoundsError(l, r))
    l2 = MutableLinkedList{T}()
    node = getNodeAt(l, first(r))
    len = length(r)
    for j in 1:len
        push!(l2, node.data)
        node = node.next
    end
    l2.len = len
    return l2
end

function Base.setindex!(l::MutableLinkedList{T}, data, idx::Int) where T
    @boundscheck 0 < idx <= l.len || throw(BoundsError(l, idx))
    node = getNodeAt(l, idx)
    node.data = convert(T, data)
    return l
end

function Base.append!(l1::MutableLinkedList{T}, l2::MutableLinkedList{T}) where T

    l1.node.prev.next = l2.node.next # l1's last's next is now l2's first
    l2.node.prev.next = l1.node # l2's last's next is now l1.node
    l1.len += length(l2)

    return l1
end

function Base.append!(l::MutableLinkedList, elts...)
    for elt in elts
        push!(l, elt)
    end
    return l
end

function Base.insert!(l::MutableLinkedList{T}, idx::Int, data) where T
    @boundscheck 0 < idx <= l.len || throw(BoundsError(l, idx))
    local node
    if idx == 1
        node = l.node.next
    elseif idx == l.len
        node = l.node.prev
    else
        node = getNodeAt(l, idx)
    end
    prev = node.prev
    
    new_node = ListNode{T}(data)
    new_node.next = node
    new_node.prev = prev
    prev.next = new_node
    node.prev = new_node

    l.len += 1

    return l
end

function Base.delete!(l::MutableLinkedList, idx::Int)
    @boundscheck 0 < idx <= l.len || throw(BoundsError(l, idx))
    node = getNodeAt(l, idx)
    prev = node.prev
    next = node.next
    prev.next = next
    next.prev = prev
    l.len -= 1
    return l
end

function Base.delete!(l::MutableLinkedList, r::UnitRange)
    @boundscheck 0 < first(r) < last(r) <= l.len || throw(BoundsError(l, r))
    node = getNodeAt(l, first(r))
    prev = node.prev
    len = length(r)
    for j in 1:len
        node = node.next
    end
    next = node
    prev.next = next
    next.prev = prev
    l.len -= len
    return l
end

function Base.push!(l::MutableLinkedList{T}, data) where T
    oldlast = l.node.prev
    node = ListNode{T}(data)
    node.next = l.node
    node.prev = oldlast
    l.node.prev = node
    oldlast.next = node
    l.len += 1
    return l
end

function Base.pushfirst!(l::MutableLinkedList{T}, data) where T
    oldfirst = l.node.next
    node = ListNode{T}(data)
    node.prev = l.node
    node.next = oldfirst
    l.node.next = node
    oldfirst.prev = node
    l.len += 1
    return l
end

function Base.pop!(l::MutableLinkedList)
    isempty(l) && throw(ArgumentError("List must be non-empty"))
    last = l.node.prev.prev
    data = l.node.prev.data
    last.next = l.node
    l.node.prev = last
    l.len -= 1
    return data
end

function Base.popfirst!(l::MutableLinkedList)
    isempty(l) && throw(ArgumentError("List must be non-empty"))
    first = l.node.next.next
    data = l.node.next.data
    first.prev = l.node
    l.node.next = first
    l.len -= 1
    return data
end

function Base.show(io::IO, node::ListNode)
    x = node.data
    print(io, "$(typeof(node))($x)")
end

function Base.show(io::IO, l::MutableLinkedList)
    print(io, typeof(l), '(')
    join(io, l, ", ")
    print(io, ')')
end
