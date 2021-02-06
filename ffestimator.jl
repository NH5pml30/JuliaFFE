using FileIO: load, save, loadstreaming, savestreaming
import LibSndFile
import PortAudio
using Unitful
using DataStructures
using StaticArrays
using Plots

function r(samples::AbstractVector{T}, ::Type{R}, lag::Int, windowSize::Int) where {T <: Number, R <: Number}
    return sum(samples[1:windowSize] .* R.(samples[lag+1:lag+windowSize]))
end

function ACFMethod(samples::AbstractVector{T}, ::Type{R}, startLag::Int, endLag::Int, windowSize::Int) where {T <: Number, R <: Number}
    # lags, lagsR = Int[], Int[]

    peakLag = -1
    peakLagR = typemin(R)
    for lag in startLag:endLag
        lagR = r(samples, R, lag, windowSize)
        if lagR > peakLagR
            peakLagR = lagR
            peakLag = lag
        end
        # push!(lags, lag)
        # push!(lagsR, lagR)
    end

    # display(plot(lags, lagsR))
    return peakLag
end

struct streamFormat{eltype <: Number}
    nchannels::Int
    samplerate::Unitful.Frequency
    endianBOM::UInt32
end

const LE_BOM = UInt32(0x04030201)
const BE_BOM = UInt32(0x01020304)

function endianBswap(endianBOM::UInt32, x)
    if endianBOM != ENDIAN_BOM
        x = bswap(x)
    end
    return x
end

function endianBswap(endianBOM::UInt32, array::AbstractArray)
    if endianBOM != ENDIAN_BOM
        array = bswap.(array)
    end
    return array
end

function endianBswap!(endianBOM::UInt32, array::AbstractArray)
    if endianBOM != ENDIAN_BOM
        array .= bswap.(array)
    end
    return
end

function endianRead(IO, endianBOM::UInt32, ::Type{T}) where {T}
    res = read(IO, T)
    return endianBswap(endianBOM, res)
end

function endianRead!(IO, endianBOM::UInt32, array::AbstractArray)
    read!(IO, array)
    endianBswap!(endianBOM, array)
    return
end

function endianWrite(IO, endianBOM::UInt32, x)
    write(IO, endianBswap(endianBOM, x))
end

function endianWrite!(IO, endianBOM::UInt32, array::AbstractArray)
    endianBswap!(endianBOM, array)
    write(IO, array)
end

function channelRead(IO, endianBOM::UInt32, nchannels::Int, ::Type{T}, n::Int) where {T}
    data = Array{T, 2}(undef, nchannels, n)
    endianRead!(IO, endianBOM, data)
    return vec(view(data, 1:1, :))
end

function estimateFundFreq(inFile, inStreamFormat::streamFormat{InT}, startFreq::Unitful.Frequency, endFreq::Unitful.Frequency, windowSize::Int,
                          outFile, outStreamFormat::streamFormat{OutT}, windowStride::Int = 1) where {InT <: Number, OutT <: Number}
    startLag, endLag = let
        noUnitsToInt = x -> Int(floor(convert(Float64, x)))

        min(noUnitsToInt(inStreamFormat.samplerate / endFreq), windowSize),
        min(noUnitsToInt(inStreamFormat.samplerate / startFreq), windowSize)
    end
    println("$startLag $endLag $windowSize")
    timeStamp = 0.0u"ms"
    samplePos = 0

    buf = CircularBuffer{InT}(2 * windowSize)
    # Read 2 windows of left channel samples
    # TODO: valid eof check
    x = channelRead(inFile, inStreamFormat.endianBOM, inStreamFormat.nchannels, InT, 2 * windowSize)
    append!(buf, x)
    # append!(ylist, x)

    while true
        # Calculate fundamental period
        period = ACFMethod(buf, Int, startLag, endLag, windowSize)

        # Generate signal samples with fundamental frequency
        # TODO: add output channels and type
        endianWrite(outFile, outStreamFormat.endianBOM,
            Float32.(sin.((samplePos .+ (0:windowStride-1)) ./ period .* (2 * pi))))

        # Write resulting frequency into file
        freq = ustrip((inStreamFormat.samplerate / period) |> u"Hz")
        push!(ylist, freq)
        # println(outFile, "$(ustrip(timeStamp |> u"ms")) $freq")

        # Move window
        # TODO: valid eof check
        if eof(inFile)
            break
        end

        popfirst!(buf)
        try
            x = channelRead(inFile, inStreamFormat.endianBOM, inStreamFormat.nchannels, InT, windowStride)
        catch e
            println(timeStamp)
            return
        end
        append!(buf, x)
        # append!(ylist, x)
        timeStamp += windowStride / inStreamFormat.samplerate
        samplePos += windowStride
    end
    println(timeStamp)
end

println("starting...")
ylist = []
open("aaa.raw", "r") do inFile
    timeStamp = 0.0u"ms"

    eltype = Int16 # typeof(f).parameters[1]
    # nchannels = LibSndFile.nchannels(inFile)
    # samplerate = LibSndFile.samplerate(inFile) * 1u"Hz"

    startFreq = 200u"Hz"
    endFreq = 800u"Hz"
    samplerate = 44100u"Hz"
    windowSize = Int(floor(convert(Float64, samplerate * 25u"ms")))

    PortAudio.PortAudioStream(1, 1; eltype=Float32, samplerate=ustrip(samplerate |> u"Hz")) do outFile
    # open("a.fx", "w") do outFile
        # Write ^L
        # write(outFile, '\f')

        println(@elapsed estimateFundFreq(inFile, streamFormat{Int16}(1, samplerate, LE_BOM), startFreq, endFreq, windowSize,
                        outFile, streamFormat{Float32}(1, samplerate, ENDIAN_BOM), 100))
    end
end

display(plot(1:length(ylist), ylist, ylim=(0, 800)))
