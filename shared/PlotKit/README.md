# PlotKit

The parts of a scientific plot that do not draw anything: the data reduction that lets a signal of millions of samples plot at the pace of the screen, the graduations of the axes, and the state of the view. MIT licence.

## What is in it

- `PeakPyramid`: a min/max pyramid over the samples of a signal. Built once (about 4 ms for a million samples, about 170 ms for fifty million), it gives the smallest and the largest sample of each column of a window in a few microseconds, whatever the zoom. A single sample far above the rest is never lost at any zoom.
- `Ticks`, `TickLabels`: graduations at 1, 2 or 5 times a power of ten with minor ticks, logarithmic graduations, labels with one unit prefix (µ, m, k, M) and the number of decimals the step needs.
- `AxisState`, `PlotViewport`, `PlotTransform`: one range per axis, linear or logarithmic, with independent zoom around a point, sliding, zoom to a box, autoscale of the vertical axis to what the horizontal range shows, and the conversion between values and positions. Every operation stays inside the bounds of the data.

The package does not draw. A view that draws with these (a SwiftUI `Canvas`, or Metal) is a separate layer.

## Tests

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```
