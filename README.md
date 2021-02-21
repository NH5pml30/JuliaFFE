# JuliaFFE
My (partial) implementation of YIN, fundamental frequency estimator for speech and music (implementation is mainly targeted at music).

Source paper: https://doi.org/10.1121/1.1458024

Implemented steps from 1-4 and 6 (step 5: parabolic interpolation is not really needed here, as samplerate in music is often enough for accurate representation).

Example program in `example.jl` reads music file and tries to play sound from fundamental frequency as if `Beep`ing. Unfortunately, music works well only if there is a strong voiceover in the song (like in example cover `badapple.raw`).
