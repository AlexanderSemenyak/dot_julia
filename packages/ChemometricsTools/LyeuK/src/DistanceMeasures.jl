"""
    SquareEuclideanDistance(X)

Returns the squared Grahm aka the euclidean distance matrix of `X`.
"""
SquareEuclideanDistance(X) = ( sum(X .^ 2, dims = 2) .+ sum(X .^ 2, dims = 2)') .- (2 * X * X')

"""
    EuclideanDistance(X)

Returns the Grahm aka the euclidean distance matrix of `X`.
"""
EuclideanDistance(X) = sqrt.(abs.(SquareEuclideanDistance(X)))

"""
    SquareEuclideanDistance(X, Y)

Returns the squared euclidean distance matrix of X and Y such that the columns are the samples in Y.
"""
SquareEuclideanDistance(X, Y) = ( sum(X .^ 2, dims = 2) .+ sum(Y .^ 2, dims = 2)') .- (2 * X * Y')

"""
    EuclideanDistance(X, Y)

Returns the euclidean distance matrix of X and Y such that the columns are the samples in Y.
"""
EuclideanDistance(X, Y) = sqrt.(abs.(SquareEuclideanDistance(X, Y)))

"""
    ManhattanDistance(X)

Returns the Manhattan distance matrix of `X`.
"""
function ManhattanDistance(X)
    Result = zeros(size(X)[1], size(X)[1])
    for rowx in 2 : (size(X)[1]), rowy in 1 : (rowx-1)
        Result[rowx, rowy] = sum( abs.( X[rowx,:] - X[rowy,:]  ) )
        Result[rowy, rowx] = Result[rowx, rowy]
    end
    return Result
end

"""
    ManhattanDistance(X, Y)

Returns the Manhattan distance matrix of X and Y such that the columns are the samples in Y.
"""
function ManhattanDistance(X, Y)
    Result = zeros(size(X)[1], size(Y)[1])
    for rowx in 1 : (size(X)[1]), rowy in 1 : size(Y)[1]
        Result[rowx, rowy] = sum( abs.( X[rowx,:] - Y[rowy,:]  ) )
    end
    return Result
end


"""
    NearestNeighbors(DistanceMatrix, N)

Returns a matrix of dimensions DistanceMatrix rows, by N columns. Basically this
goes through each row and finds the ones corresponding column which has the smallest distance.
"""
function NearestNeighbors(DistanceMatrix, N)
    Result = zeros( size( DistanceMatrix )[ 1 ], N )
    for rowx in 1 : ( size( DistanceMatrix )[ 1 ] )
        Result[rowx, :] = sortperm( DistanceMatrix[ rowx, : ] )[ 1 : N ]
    end
    return Result
end

"""
    NearestNeighbors(DistanceMatrix)

Returns the nearest neighbor adjacency matrix from a given `DistanceMatrix`.
"""
function AdjacencyMatrix(DistanceMatrix)
    Result = zeros( size( DistanceMatrix )[ 1 ], N )
    for rowx in 1 : ( size( DistanceMatrix )[ 1 ] )
        NN = sortperm( DistanceMatrix[ rowx, : ] )[ 1 : N ]
        Result[ rowx, : ] = NN
        #Result[ : , rowx] = NN
    end
    return Result
end

"""
    InClassAdjacencyMatrix(DistanceMatrix, YHOT, K = 1)

Computes the in class Adjacency matrix with K nearest neighbors.
"""
function InClassAdjacencyMatrix(DistanceMatrix, YHOT, K = 1)
    Result = zeros( size( DistanceMatrix ) )
    for rowx in 1 : ( size( DistanceMatrix )[ 1 ] )
        ClassNumber = findfirst( YHOT[ rowx, : ] .== 1 )
        ClassInstances = findall( YHOT[ :, ClassNumber ] .== 1 )
        ClassInstances = setdiff(ClassInstances, rowx)
        k = K
        if length(ClassInstances) < K
            k = length(ClassInstances)
        end
        NN = sortperm( DistanceMatrix[ rowx, ClassInstances ] )[ 1 : k ]
        Result[ rowx, NN ] .= 1#.+= 1
    end
    return Result
end

"""
    OutOfClassAdjacencyMatrix(DistanceMatrix, YHOT, K = 1)

Computes the out of class Adjacency matrix with K nearest neighbors.
"""
function OutOfClassAdjacencyMatrix(DistanceMatrix, YHOT, K = 1)
    Result = zeros( size( DistanceMatrix ) )
    for rowx in 1 : ( size( DistanceMatrix )[ 1 ] )
        ClassNumber = findfirst( YHOT[ rowx, : ] .== 1 )
        ClassInstances = findall( YHOT[ :, ClassNumber ] .== 0 )
        k = K
        if length(ClassInstances) < K
            k = length(ClassInstances)
        end
        NN = sortperm( DistanceMatrix[ rowx, ClassInstances ] )[ 1 : k ]
        Result[ rowx, NN ] .= 1#.+= 1
    end
    return Result
end



#Kernels
struct Kernel
    params::Union{Float64, Tuple}
    ktype::String
    original::Array
end
"""
    Kernel(X)

Default constructor for Kernel object. Returns the linear kernel of `X`.
"""
Kernel( X ) = Kernel(0.0, "linear", X)

#This is just a wrapper so we can apply kernels willy nilly in one line
"""
    (K::Kernel)(X)

This is a convenience function to allow for one-line construction of kernels from a Kernel object `K` and new data `X`.
"""
function (K::Kernel)(X)
    if K.ktype == "linear"
        return LinearKernel(K.original, X, K.params)
    elseif K.ktype == "gaussian" || K.ktype == "rbf"
        return GaussianKernel(K.original , X, K.params)
    end
end

"""
    LinearKernel(X, c)

Creates a Linear kernel from Array `X` and hyperparameter `C`.
"""
LinearKernel(X, c) =  (X * X') .+ c

"""
    LinearKernel(X, Y, c)

Creates a Linear kernel from Arrays `X` and `Y` with hyperparameter `C`.
"""
LinearKernel(X, Y, c) = (Y * X') .+ c

"""
    GaussianKernel(X, sigma)

Creates a Gaussian/RBF kernel from Array `X` using hyperparameter `sigma`.
"""
function GaussianKernel(X, sigma)
    Gamma = -1.0 / (2.0 * sigma^2)
    return exp.( SquareEuclideanDistance(X) .* Gamma  )
end

"""
    GaussianKernel(X, Y, sigma)

Creates a Gaussian/RBF kernel from Arrays `X` and `Y` with hyperparameter `sigma`.
"""
function GaussianKernel(X, Y, sigma)
    Gamma = -1.0 / (2.0 * sigma^2)
    return exp.( SquareEuclideanDistance(Y, X) .* Gamma  )
end


"""
    CauchyKernel(X, sigma)

Creates a Cauchy kernel from Array `X` using hyperparameters `sigma`.
"""
function CauchyKernel(X, sigma)
    return 1.0 ./ ( (pi * sigma) .* (1.0 .+ ( SquareEuclideanDistance(X) ./ sigma) .^ 2  ) )
end


"""
    CauchyKernel(X, Y, sigma)

Creates a Cauchy kernel from Arrays `X` and `Y` using hyperparameters `sigma`.
"""
function CauchyKernel(X, Y, sigma)
    return 1.0 ./ ( (pi * sigma) .* (1.0 .+ ( SquareEuclideanDistance(Y, X) ./ sigma) .^ 2  ) )
end
