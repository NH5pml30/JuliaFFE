include("./ffestimator.jl")
using .FFEstimator

using FileIO: load, save, loadstreaming, savestreaming
using Unitful
import LibSndFile
import PortAudio
using Plots

freqs, certs = [], []
xlist = []

open("badapple.raw", "r") do inFile
    startFreq = 200u"Hz"
    endFreq = 800u"Hz"

    samplerate = 48000u"Hz"
    nchannels = 2
    eltype = Float32
    ebom = LE_BOM

    windowSize = trunc(Int, convert(Float64, samplerate * 25u"ms"))
    windowStride = 75

    PortAudio.PortAudioStream(1, 1; eltype=Float32, samplerate=ustrip(samplerate |> u"Hz")) do outFile
        for (period, freq, samplePos, timeStamp, certainty) in
                FFreqEstimator{Float64}(inFile, streamFormat{eltype}(nchannels, samplerate, ebom),
                                        startFreq, endFreq, windowSize, windowStride, 750u"ms")
            push!(freqs, freq)
            push!(xlist, timeStamp)
            push!(certs, certainty)
            write(outFile, Float32.(sin.((samplePos .+ (0:windowStride-1)) ./ period .* (2 * pi))))
        end
    end
end

plot(xlist, freqs, ylim=(200, 800))
display(plot!(twinx(), xlist, certs, linecolor="red"))
