using FileIO: load, save, loadstreaming, savestreaming
using Unitful

export streamFormat, LE_BOM, BE_BOM

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

function normalizedChannelRead(IO, endianBOM::UInt32, nchannels::Int, ::Type{T}, ::Type{R}, n::Int) where {T <: Number, R <: Real}
    data = Array{T, 2}(undef, nchannels, n)
    endianRead!(IO, endianBOM, data)
    if T <: Int
        return vec(view(data, 1:1, :)) .* 1.0 ./ typemax(T)
    end
    return vec(view(data, 1:1, :))
end
