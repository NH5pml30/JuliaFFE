using FileIO: open, close, read, write
using Plots

function addToPlot!(plot, xlist, ylist)
    plot!(plot, xlist, ylist)
    empty!(xlist)
    empty!(ylist)
    return
end

xlist, ylist = [], []
p = plot([], [], xlim=(0, 1250), ylim=(0, 200))
open("rl001.fx", "r") do io
    let
        skip_flag = true
        skipchars(ch -> (skip_flag &= (ch != '\f')) || ch == '\f', io)
    end
    for line in eachline(io)
        if line == ""
            continue
        end

        xy = map(str -> tryparse(Float32, str), split(line))
        if length(xy) != 2 || xy[1] == Nothing || xy[2] == Nothing
            if line == "="
                addToPlot!(p, xlist, ylist)
            else
                println("Invalid format")
                exit(0)
            end
        else
            x, y = xy
            append!(xlist, x)
            append!(ylist, y)
        end
    end
end

if !isempty(xlist)
    addToPlot!(p, xlist, ylist)
end

display(p)
