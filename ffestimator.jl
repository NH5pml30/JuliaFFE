using FileIO: load, save, loadstreaming, savestreaming
import LibSndFile
import PortAudio
using Unitful
using DataStructures
using StaticArrays

function r(samples::AbstractVector{T}, lag::Int, windowSize::Int) where {T <: Number}
    return sum(samples[1:windowSize] .* samples[lag+1:lag+windowSize])
end

function ACFMethod(samples::AbstractVector{T}, startLag::Int, endLag::Int, windowSize::Int) where {T <: Number}
    lags, lagsR = Int[], Int[]

    peakLag = -1
    peakLagR = typemin(Int)
    for lag in startLag:endLag
        lagR = r(samples, lag, windowSize)
        if lagR > peakLagR
            peakLagR = lagR
            peakLag = lag
        end
        push!(lags, lag)
        push!(lagsR, lagR)
    end

    # display(plot(lags, lagsR))
    return peakLag
end

println("starting...")
ylist = Int[]
open("rl001.sig", "r") do inFile
    timeStamp = 0.0u"ms"

    eltype = Int16 # typeof(f).parameters[1]
    # nchannels = LibSndFile.nchannels(inFile)
    # samplerate = LibSndFile.samplerate(inFile) * 1u"Hz"

    startFreq = 40u"Hz"
    endFreq = 800u"Hz"

    samplerate = 20000u"Hz"
    windowSize = Int(floor(convert(Float64, samplerate * 25u"ms")))
    startLag = Int(floor(convert(Float64, samplerate / endFreq)))
    endLag = Int(floor(convert(Float64, samplerate / startFreq)))

    println("$startLag $endLag $windowSize")

    # PortAudio.PortAudioStream(nchannels, 1; eltype=eltype, samplerate=samplerate) do stream
    open("a.fx", "w") do outFile
        # Write ^L
        write(outFile, '\f')

        buf = CircularBuffer{eltype}(2 * windowSize)
        # Read 2 windows of left channel samples
        x = Vector{eltype}(undef, 2 * windowSize)
        read!(inFile, x)
        x .= bswap.(x)
        # append!(buf, vec(view(x, :, 1:1)))
        append!(buf, x)
        append!(ylist, x)
        while true
            # Calculate fundamental period
            period = ACFMethod(buf, startLag, endLag, windowSize)

            # Generate signal samples with fundamental frequency
            # for i in 1:windowSize
            #     write(stream, [Float32(sin(i / period * 2 * pi))])
            # end

            # Write resulting frequency into file
            freq = ustrip(uconvert(u"Hz", samplerate / period))
            println(outFile, "$(ustrip(timeStamp)) $freq")

            # Move window
            if eof(inFile)
                break
            end

            popfirst!(buf)
            y = bswap(read(inFile, eltype))
            push!(buf, y)
            push!(ylist, y)
            timeStamp += 1 / samplerate
        end
    end
end

display(plot(1:length(ylist), ylist))
