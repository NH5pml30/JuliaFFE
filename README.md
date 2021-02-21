# JuliaFFE
My (partial) implementation of YIN, fundamental frequency estimator for speech and music (implementation is mainly targeted at music).

Source paper: https://doi.org/10.1121/1.1458024

Implemented steps from 1-4 and 6 (step 5: parabolic interpolation is not really needed here, as samplerate in music is often enough for accurate representation).

Example program in `example.jl` reads music file and tries to play sound from fundamental frequency as if `Beep`ing. Unfortunately, music works well only if there is a strong voiceover in the song (like in example cover `badapple.raw`).

`Plotter.jl` is a tool to read and plot `*.fx` files with accurate fundamental frequency (for testing the method on a database). Examples here are `rl001.fx` (laryngeal frequency contour) and `rl001.sig` with voice samples (20kHz, 16-bits (Headerless file),	big-endian) - from database that can be downloaded here: (https://www.cstr.ed.ac.uk/research/projects/fda/fda_eval.tar.gz).

The track segment uploaded in this repository (`badapple.raw`) is for educational and research purposes only. The track is a property of its owner ([Bad Apple!! (English Cover)](https://www.youtube.com/watch?v=rQg2qngyIZM) by [JubyPhonic](https://jubyphonic.carrd.co)).
