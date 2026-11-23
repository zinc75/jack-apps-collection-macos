# PlotKit

Scientific plots for SwiftUI on macOS: a signal of millions of samples that plots at the pace of the screen, curves for the frequency domain, and what a window needs around a plot (a toolbar, an inspector, a minimap, a range that can be edited). The package knows nothing about audio files or about any tool: the application gives it samples, curves and names. macOS 15, MIT licence.

## Plots

`SignalPlot` draws a signal in time. Up to one pixel per sample it draws the envelope of each column of pixels, with a gradient or a flat fill; from one pixel between two samples it joins them by a line, and from seven pixels it draws stems with a head. The vertical axis is linear or in decibels, the horizontal one is in samples or in time. A crosshair gives the values on the axes and a card at the nearest sample, a box zoom and a measure give a time, a level and the frequency of the interval. Several signals can share a plot, each in its own colour.

`CurvePlot` is the same plot for curves whose abscissas are not regular: the magnitude of a spectrum, its phase, a group delay. The horizontal axis is linear or logarithmic, the vertical one linear or in decibels. A curve with many more points than the view has pixels is reduced to the extremes of each column. The measure gives the ratio of two frequencies in octaves. For a phase the display options can unwrap it, take its delay out, or show the group delay instead (from the transform of n·h[n], not from the slope of the phase). For a magnitude and a group delay they can smooth it in a fraction of an octave, from 1/24 to 1 octave, with the raw curve kept behind it, thin and pale.

Both plots take the same gestures: a pinch or the wheel of a mouse zooms around the pointer (with ⌥ on the vertical axis only, with ⇧ on both), a precise scroll slides, with ⌘ it zooms, a drag on an axis slides it or changes its scale, a double click shows everything. The events come from an AppKit layer, because SwiftUI gestures cannot tell a wheel from a trackpad or read the modifier keys of a scroll.

## Data

`PeakPyramid` is a min/max pyramid over the samples of a signal. It is built once (about 4 ms for a million samples, about 170 ms for fifty million) and gives the smallest and the largest sample of each column of a window in a few microseconds, whatever the zoom: a single sample far above the rest is never lost. `PlotSignal` is the protocol the views read, so that a signal that grows while it is recorded can take the place of the pyramid of a finished one.

`AxisState`, `PlotViewport` and `PlotTransform` hold one range per axis, linear or logarithmic, with zoom around a point, sliding, zoom to a box, autoscale of the vertical axis to what the horizontal range shows, and the conversion between values and positions. Every operation stays inside the bounds of the data, and `AxisState.switched(to:)` changes the scale of an axis while keeping the range as close as it can. `Ticks` and `TickLabels` give graduations at 1, 2 or 5 times a power of ten with minor ticks, logarithmic graduations, and labels with one unit prefix and the number of decimals the step needs.

## Channels

`PlotSeriesSet` holds the channels of a file: a name, a colour the person can choose and whether it is shown. The same set feeds the plot in time, the spectrum and the phase, so a channel keeps its colour in every view. `PlotChannelList` lists them one under the other (show or hide, colour, show alone, reorder by dragging) and fits an inspector. `PlotLegend` is the same selector as a row of chips.

## A range of the horizontal axis

`PlotOverview` is a minimap of the whole signal that follows the horizontal axis of the plot: a rounded container, the signal, and a frame that is the part the plot shows, with solid ends to drag. Drag the ends to zoom, the part between them to slide, or press outside it to bring the plot there. A second range can be shown in it without being editable. Two styles exist, `trim` (the frame of the trim control of QuickTime) and `glass`.

`PlotRegionEditor` makes a range editable in the plot itself: two sliders on a rail under the plot, as the levels of the color adjustment of Preview have, dotted lines across the plot, and what is outside dimmed. While a slider is dragged, bubbles say where the ends are, in the units `PlotRegionStyle.format` gives (a sample number and the time it makes, for instance). The range is updated during the drag and `onCommit` is called when it ends, so an application with an undo history records one change. A style gives the colour (with another for a light appearance if needed), the smallest length, the bounds and whether the ends are whole numbers.

`PlotZoneBar` edits the same kind of range under a plot of something else. It looks like the minimap, but its frame is the range, a fine dotted line, and what it changes is the range itself, not the part that a plot shows. Under it is a rail with the same sliders as the ones under the plot of a region, a little smaller, so the range is edited the same way in both. A spectrum computed on a part of a signal is the typical use: the bar under it moves the part, and the spectrum follows.

## A window around a plot

`PlotController` is the state a plot shares with the window around it: the mode of the drag, the commands, the scales, the display options and the state of the inspector. A window that gives its plot a controller puts `PlotToolbarContent` in its toolbar, so the buttons look like those of the other tools of the window; without a controller the plot has a strip of its own.

`PlotInspector` is the inspector of such a window, on the model of the inspectors of the editors of the system: text tabs at the top, and sections with a chevron that folds them, an optional box in the title and an "i" that opens the long explanation in a popover. An application adds its own pages with `PlotInspectorTab`, built from `PlotInspectorSection`s, after the pages of the plot or before them (`leadingTabs`, the first one being open at first). `PlotInspectorToolbarContent` holds the help and the button that shows and hides the inspector.

`plotOverlayInspector` shows an inspector as a panel of glass at the right edge of a window: over the plot when the window is narrow, or with `docked` keeping its room beside it, so that both look the same. It replaces the system's inspector where the window has to switch between the two. A floating panel closes itself when a click lands elsewhere in the window (`onOutsideClick`), as a popover does; the click still goes where it was meant to. A click on a handle of a region (its knobs, its rail, its edges, the bar of a range) or along the border of the window, where it is taken to be resized, does not close it. `plotWindowWidth` reads the width of the window itself, which does not change when the panel opens.

SwiftUI lays a toolbar out once and does not do it again when an inspector opens or closes, so the items that belong to the side of the inspector stay where they were. `ToolbarRelayout`, put in the background of the content, asks the window to lay it out again by resizing it by two points and back.

`PlotAnnotations` and `PlotMarker` mark places of the horizontal axis (the start of an attack, the end of a tail) with a name and a colour. `PlotLabels` holds every text the package shows, so that an application gives its own language; the default is English.

## Tests

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

## Licence

MIT, see `LICENSE`.
