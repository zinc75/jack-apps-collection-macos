# PlotKit

The parts of a scientific plot that do not draw anything: the data reduction that lets a signal of millions of samples plot at the pace of the screen, the graduations of the axes, and the state of the view. MIT licence.

## What is in it

- `PeakPyramid`: a min/max pyramid over the samples of a signal. Built once (about 4 ms for a million samples, about 170 ms for fifty million), it gives the smallest and the largest sample of each column of a window in a few microseconds, whatever the zoom. A single sample far above the rest is never lost at any zoom.
- `Ticks`, `TickLabels`: graduations at 1, 2 or 5 times a power of ten with minor ticks, logarithmic graduations, labels with one unit prefix (µ, m, k, M) and the number of decimals the step needs.
- `AxisState`, `PlotViewport`, `PlotTransform`: one range per axis, linear or logarithmic, with independent zoom around a point, sliding, zoom to a box, autoscale of the vertical axis to what the horizontal range shows, and the conversion between values and positions. Every operation stays inside the bounds of the data.

- `SignalPlot`: a SwiftUI view that draws a signal with them. The envelope of the columns with a gradient, the samples joined by a line from one pixel between two of them, and as stems with a head from seven, in linear amplitude or in decibels, graduated axes in samples or in time, a crosshair with the values on the axes and a card at the nearest sample, a box zoom, a measure of a time and a level (with the frequency of the interval), and the controls of Plotly: a toolbar of modes, zoom, autoscale and reset, with an "i" that lists the gestures. A window that has a toolbar of its own gives the plot a `PlotController` and puts `PlotToolbarContent` in it, so the buttons look like those of the other tools of the window; without one, the plot has a strip of its own. A pinch, the wheel of a mouse and the zoom buttons zoom (with ⌥ the vertical axis only, with ⇧ both), a precise scroll slides (with ⌘ it zooms), a drag on an axis slides it or changes its scale, a double click shows everything. The events come from an AppKit layer because SwiftUI gestures cannot tell a wheel from a trackpad or read the modifier keys of a scroll.
- `CurvePlot`: the same plot for curves whose abscissas are not regular, for the frequency domain (the magnitude of a spectrum, its phase, a group delay). The horizontal axis is linear or logarithmic and the vertical one linear or in decibels; a window that has a `PlotController` gets menus for both in its toolbar. A curve is drawn as it is, or reduced to the extremes of each column of pixels when it has many more points than the view has pixels. The measure gives the ratio of two frequencies in octaves.
- Options of the inspector for the curves of a spectrum: smoothing of the magnitude in a fraction of an octave (1/24 to 1 octave, the power averaged in the band, with the raw spectrum kept behind it), unwrapping of a phase, and removal of its delay.
- `PlotSignal`: what the view reads, so that a signal that grows while it is recorded can take the place of the pyramid of a finished one.

An axis can be linear or logarithmic, and `AxisState.switched(to:)` changes it while keeping the range as close as it can (a logarithmic axis starts where the data does, and the bounds come back on the return). The graduations and the labels of the view follow the scale of each axis.

## Tests

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```
