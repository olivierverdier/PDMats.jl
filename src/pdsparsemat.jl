"""
Sparse positive definite matrix together with a Cholesky factorization object.
"""
struct PDSparseMat{T<:Real,S<:AbstractSparseMatrix} <: AbstractPDMat{T}
    dim::Int
    mat::S
    chol::CholTypeSparse

    PDSparseMat{T,S}(d::Int,m::AbstractSparseMatrix{T},c::CholTypeSparse) where {T,S} =
        new{T,S}(d,m,c) #add {T} to CholTypeSparse argument once #14076 is implemented
end

function PDSparseMat(mat::AbstractSparseMatrix,chol::CholTypeSparse)
    d = size(mat, 1)
    size(chol, 1) == d ||
        throw(DimensionMismatch("Dimensions of mat and chol are inconsistent."))
    PDSparseMat{eltype(mat),typeof(mat)}(d, mat, chol)
end

PDSparseMat(mat::SparseMatrixCSC) = PDSparseMat(mat, cholesky(mat))
PDSparseMat(fac::CholTypeSparse) = PDSparseMat(sparse(fac), fac)

AbstractPDMat(A::SparseMatrixCSC) = PDSparseMat(A)
AbstractPDMat(A::CholTypeSparse) = PDSparseMat(A)

### Conversion
Base.convert(::Type{PDSparseMat{T}}, a::PDSparseMat{T}) where {T<:Real} = a
function Base.convert(::Type{PDSparseMat{T}}, a::PDSparseMat) where {T<:Real}
    # CholTypeSparse only supports Float64 and ComplexF64 type parameters!
    # So there is no point in recomputing `cholesky(mat)` and we just reuse
    # the existing Cholesky factorization
    mat = convert(AbstractMatrix{T}, a.mat)
    return PDSparseMat{T,typeof(mat)}(a.dim, mat, a.chol)
end
Base.convert(::Type{AbstractPDMat{T}}, a::PDSparseMat) where {T<:Real} = convert(PDSparseMat{T}, a)

### Basics

Base.size(a::PDSparseMat) = (a.dim, a.dim)
Base.Matrix(a::PDSparseMat) = Matrix(a.mat)
LinearAlgebra.diag(a::PDSparseMat) = diag(a.mat)
LinearAlgebra.cholesky(a::PDSparseMat) = a.chol

### Inheriting from AbstractMatrix

Base.getindex(a::PDSparseMat,i::Integer) = getindex(a.mat, i)
Base.getindex(a::PDSparseMat,I::Vararg{Int, N}) where {N} = getindex(a.mat, I...)

### Arithmetics

# add `a * c` to a dense matrix `m` of the same size inplace.
function pdadd!(r::Matrix, a::Matrix, b::PDSparseMat, c)
    @check_argdims size(r) == size(a) == size(b)
    _addscal!(r, a, b.mat, c)
end

*(a::PDSparseMat, c::Real) = PDSparseMat(a.mat * c)
*(a::PDSparseMat, x::AbstractMatrix) = a.mat * x  # defining these seperately to avoid
*(a::PDSparseMat, x::AbstractVector) = a.mat * x  # ambiguity errors
\(a::PDSparseMat{T}, x::AbstractVecOrMat{T}) where {T<:Real} = convert(Array{T},a.chol \ convert(Array{Float64},x)) #to avoid limitations in sparse factorization library CHOLMOD, see e.g., julia issue #14076
/(x::AbstractVecOrMat{T}, a::PDSparseMat{T}) where {T<:Real} = convert(Array{T},convert(Array{Float64},x) / a.chol )

### Algebra

Base.inv(a::PDSparseMat{T}) where {T<:Real} = PDMat(inv(a.mat))
LinearAlgebra.det(a::PDSparseMat) = det(a.chol)
LinearAlgebra.logdet(a::PDSparseMat) = logdet(a.chol)
LinearAlgebra.sqrt(A::PDSparseMat) = PDMat(sqrt(Hermitian(Matrix(A))))

### whiten and unwhiten

function whiten!(r::AbstractVecOrMat, a::PDSparseMat, x::AbstractVecOrMat)
    # Can't use `ldiv!` due to missing support in SparseArrays
    return copyto!(r, chol_lower(a.chol) \ x)
end

function unwhiten!(r::AbstractVecOrMat, a::PDSparseMat, x::AbstractVecOrMat)
    # `*` is not defined for `PtL` factor components,
    # so we can't use `chol_lower(a.chol) * x`
    C = a.chol
    PtL = sparse(C.L)[C.p, :]
    # Can't use `lmul!` due to missing support in SparseArrays
    return copyto!(r, PtL * x)
end


### quadratic forms

quad(a::PDSparseMat, x::AbstractVector) = dot(x, a * x)
invquad(a::PDSparseMat, x::AbstractVector) = dot(x, a \ x)

function quad!(r::AbstractArray, a::PDSparseMat, x::AbstractMatrix)
    @check_argdims eachindex(r) == axes(x, 2)
    for i in axes(x, 2)
        r[i] = quad(a, x[:,i])
    end
    return r
end

function invquad!(r::AbstractArray, a::PDSparseMat, x::AbstractMatrix)
    @check_argdims eachindex(r) == axes(x, 2)
    for i in axes(x, 2)
        r[i] = invquad(a, x[:,i])
    end
    return r
end


### tri products

function X_A_Xt(a::PDSparseMat, x::AbstractMatrix)
    # `*` is not defined for `PtL` factor components,
    # so we can't use `x * chol_lower(a.chol)`
    C = a.chol
    PtL = sparse(C.L)[C.p, :]
    z = x * PtL
    z * transpose(z)
end


function Xt_A_X(a::PDSparseMat, x::AbstractMatrix)
    # `*` is not defined for `UP` factor components,
    # so we can't use `chol_upper(a.chol) * x`
    # Moreover, `sparse` is only defined for `L` factor components
    C = a.chol
    UP = transpose(sparse(C.L))[:, C.p]
    z = UP * x
    transpose(z) * z
end


function X_invA_Xt(a::PDSparseMat, x::AbstractMatrix)
    z = a.chol \ collect(transpose(x))
    x * z
end

function Xt_invA_X(a::PDSparseMat, x::AbstractMatrix)
    z = a.chol \ x
    transpose(x) * z
end
