module FFEstimator

using Unitful
using DataStructures

include("./io.jl")

export FFreqEstimator

# Autocorellation function of lag
function r(samples::AbstractVector{T}, lag::Int, windowSize::Int) where {T <: Number}
    return sum(@view(samples[1:windowSize]) .* @view(samples[lag+1:lag+windowSize]))
end

# Struct for optimizing `d` function execution time (iterative sum)
mutable struct DCache{T <: Number}
    prevSuffixSum::Vector{T} # terms that are in both previous and current sum
    # lag range from last iteration for removal of stale values
    lastStart::Int
    lastEnd::Int

    DCache{T}() where {T <: Number} = new{T}([], 0, 0)
end

# Stride cache one step function
function strideCache(d_cache::DCache{T}) where {T <: Number}
    d_cache.prevSuffixSum[1:d_cache.lastStart-1] .= T(-1)
    resize!(d_cache.prevSuffixSum, d_cache.lastEnd)
    d_cache.lastStart = d_cache.lastEnd = 0
end

# Difference function of lag (optimized)
function d(d_cache::DCache{T}, samples::AbstractVector{T}, lag::Int, windowSize::Int, windowStride::Int) where {T <: Number}
    if d_cache.lastStart == 0
        d_cache.lastStart = lag
    end
    d_cache.lastEnd = lag

    func = (b, e) -> sum((@view(samples[b:e]) .- @view(samples[lag+b:lag+e])) .^ 2)
    if windowStride * 3 <= windowSize
        # window stride is small compared to window size, can optimize
        prefix = func(1, windowStride)
        if length(d_cache.prevSuffixSum) < lag
            push!(d_cache.prevSuffixSum, -1)
        end
        if d_cache.prevSuffixSum[lag] < 0
            # previous value is not evaluated => evaluate everything now
            res = prefix + func(windowStride+1, windowSize)
        else
            # use previous value
            suffix = func(windowSize - windowStride + 1, windowSize)
            res = d_cache.prevSuffixSum[lag] + suffix
        end
        # save for future generations
        d_cache.prevSuffixSum[lag] = res - prefix
        return res
    else
        # optimization is not worth it
        return func(1, windowSize)
    end
end

# Cumulative mean normalized difference function
function d_prime(d_cache::DCache{T}, samples::AbstractVector{T}, prefixSum::T, lag::Int, windowSize::Int, windowStride::Int) where {T <: Number}
    if lag == 0
        return (T(1), T(0))
    else
        d_lag = d(d_cache, samples, lag, windowSize, windowStride)
        return (d_lag / (1 / lag * (prefixSum + d_lag)), prefixSum + d_lag)
    end
end

# Make argmin, argmax work for generators
Base.keys(g::Base.Generator) = g.iter

# Autocorellation function peak
function ACFMethod(samples::AbstractVector{T}, startLag::Int, endLag::Int, windowSize::Int) where {T <: Number}
    return argmax(r(samples, lag, windowSize) for lag in startLag:endLag)
end

# Difference function dip
function DFMethod(d_cache::DCache{T}, samples::AbstractVector{T}, startLag::Int, endLag::Int, windowSize::Int, windowStride::Int) where {T <: Number}
    return argmin(d(d_cache, samples, lag, windowSize, windowStride) for lag in startLag:endLag)
end

# Cumulative mean normalized difference function dip
function CMNDFMethod(d_cache::DCache{T}, samples::AbstractVector{T}, startLag::Int, endLag::Int, windowSize::Int, windowStride::Int) where {T <: Number}
    prefixSum = sum(d(d_cache, samples, lag, windowSize, windowStride) for lag in 1:startLag-1)
    foundThreshold = false
    foundThresholdDip = false
    lastRes, minRes = typemax(T), typemax(T)
    toret = argmin(
        let
            if foundThresholdDip
                # evade too high errors and drop out
                typemax(T)
            else
                res, prefixSum = d_prime(d_cache, samples, prefixSum, lag, windowSize, windowStride)
                if res < minRes
                    minRes = res
                end
                if res < 0.1
                    # found acceptable value already, wait for minimum
                    foundThreshold = true
                end
                if foundThreshold && !foundThresholdDip && res > lastRes
                    # already found minimum after acceptable value, drop out
                    foundThresholdDip = true
                    res = typemax(T)
                end
                lastRes = res
                res
            end
        end
        for lag in startLag:endLag)
    return (toret, minRes)
end

# Fundamental frequency estimator struct (with data related to current audio stream)
struct FFreqEstimator{InT <: Number, EvalT <: Number}
    inFile
    inStreamFormat::streamFormat{InT}

    # fundamental period search range
    startLag::Int
    endLag::Int
    # window data
    windowSize::Int
    windowStride::Int
    # radius for best local estimate search
    shoppingRadius::Int

    # samples buffer
    buf::CircularBuffer{EvalT}

    function FFreqEstimator{EvalT}(inFile, inStreamFormat::streamFormat{InT},
                                   startFreq::Unitful.Frequency, endFreq::Unitful.Frequency,
                                   windowSize::Int, windowStride::Int,
                                   filterDuration::Unitful.Time) where {InT <: Number, EvalT <: Number}
        startLag, endLag, shoppingRadius = let
            noUnitsToInt = x -> trunc(Int, convert(Float64, x))

            min(noUnitsToInt(inStreamFormat.samplerate / endFreq), windowSize),
            min(noUnitsToInt(inStreamFormat.samplerate / startFreq), windowSize),
            noUnitsToInt((filterDuration / 2 * inStreamFormat.samplerate) / windowSize)
        end

        new{InT, EvalT}(inFile, inStreamFormat, startLag, endLag,
                        windowSize, windowStride, shoppingRadius,
                        CircularBuffer{EvalT}(2 * windowSize + shoppingRadius * windowStride))
    end
end

# Estimate fundamental period with best method function
function estimate(data::FFreqEstimator{InT, EvalT}, d_cache::DCache{EvalT}, offset::Int, startLag::Int = data.startLag, endLag::Int = data.endLag) where {InT <: Number, EvalT <: Number}
    res = CMNDFMethod(d_cache, @view(data.buf[offset+1:offset+2*data.windowSize]), startLag, endLag, data.windowSize, data.windowStride)
    strideCache(d_cache)
    return res
end

# Interface for fundamental frequency estimation (begin iteration)
function Base.iterate(data::FFreqEstimator{InT, EvalT}) where {InT <: Number, EvalT <: Number}
    shoppedEsts = Deque{Tuple{Int, EvalT}}()
    Cache1, Cache2 = DCache{EvalT}(), DCache{EvalT}()
    try
        x = normalizedChannelRead(data.inFile, data.inStreamFormat.endianBOM, data.inStreamFormat.nchannels,
                                  InT, EvalT, 2 * data.windowSize + data.shoppingRadius * data.windowStride)
        append!(data.buf, x)

        for _ in 1:data.shoppingRadius
            push!(shoppedEsts, (0, typemax(InT)))
        end
        for i in 0:data.shoppingRadius
            push!(shoppedEsts, estimate(data, Cache1, i*data.windowStride))
        end
    catch e
        if !isa(e, EOFError)
            throw(e)
        end
        return nothing
    end
    return Base.iterate(data, (0, 0, shoppedEsts, Cache1, Cache2, 400))
end

# Interface for fundamental frequency estimation (continue iteration)
function Base.iterate(data::FFreqEstimator{InT}, (samplePos, timeStamp, shoppedEsts, Cache1, Cache2, currentPeriod)) where {InT <: Number}
    # get predicted period from around here
    (predictedPeriod, predictedVal) = argmin(val_ for (period_, val_) in shoppedEsts)

    # Method from paper does not work really well with music, so just select best period from local range
    # (period, val) = estimate(data, Cache2, 0,
    #                          trunc(Int, max(predictedPeriod * 0.8, data.startLag)),
    #                          trunc(Int, min(predictedPeriod * 1.2, data.endLag)))
    currentPeriod = predictedPeriod
    freq = ustrip((data.inStreamFormat.samplerate / currentPeriod) |> u"Hz")

    # move window
    for _ in 1:data.windowStride popfirst!(data.buf) end
    x = nothing
    try
        x = channelRead(data.inFile, data.inStreamFormat.endianBOM, data.inStreamFormat.nchannels, InT, data.windowStride)
    catch e
        if !isa(e, EOFError)
            throw(e)
        end
        return nothing
    end
    append!(data.buf, x)

    popfirst!(shoppedEsts)
    push!(shoppedEsts, estimate(data, Cache1, data.shoppingRadius*data.windowStride))

    certainty = let
        from, to = 0.75, 1.25
        clamp((to - predictedVal) / (to - from), 0, 1)
    end

    return ((currentPeriod, freq, samplePos, timeStamp, certainty),
            (
                samplePos += data.windowStride,
                timeStamp += ustrip((data.windowStride / data.inStreamFormat.samplerate) |> u"ms"),
                shoppedEsts, Cache1, Cache2, currentPeriod
            ))
end

end # module
