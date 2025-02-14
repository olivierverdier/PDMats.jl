using LinearAlgebra, PDMats
using PDMats: chol_lower, chol_upper

@testset "chol_lower and chol_upper" begin
    @testset "allocations" begin
        A = rand(100, 100)
        C = A'A
        size_of_one_copy = sizeof(C)
        @assert size_of_one_copy > 100  # ensure the matrix is large enough that few-byte allocations don't matter

        @test chol_lower(C) ≈ chol_upper(C)'
        @test (@allocated chol_lower(C)) < 1.05 * size_of_one_copy  # allow 5% overhead
        @test (@allocated chol_upper(C)) < 1.05 * size_of_one_copy

        for uplo in (:L, :U)
            ch = cholesky(Symmetric(C, uplo))
            @test chol_lower(ch) ≈ chol_upper(ch)'
            @test (@allocated chol_lower(ch)) < 33  # allow small overhead for wrapper types
            @test (@allocated chol_upper(ch)) < 33  # allow small overhead for wrapper types
        end
    end

    # issue #120
    @testset "correctness with pivoting" begin
        A = [2 1 1; 1 2 0; 1 0 2]
        x = randn(3)

        # Compute `invquad` without explicit factorization
        b = x' * (A \ x)

        @test sum(abs2, PDMats.chol_lower(A) \ x) ≈ b
        @test sum(abs2, PDMats.chol_upper(A)' \ x) ≈ b

        for uplo in (:L, :U)
            # dense version
            ch_dense = cholesky(Symmetric(A, uplo))
            @test sum(abs2, PDMats.chol_lower(ch_dense) \ x) ≈ b
            @test sum(abs2, PDMats.chol_upper(ch_dense)' \ x) ≈ b

            # sparse version
            if PDMats.HAVE_CHOLMOD
                ch_sparse = cholesky(Symmetric(sparse(A), uplo))
                @test sum(abs2, PDMats.chol_lower(ch_sparse) \ x) ≈ b
                @test sum(abs2, PDMats.chol_upper(ch_sparse)' \ x) ≈ b
            end
        end
    end
end
