// SPDX-License-Identifier: MIT

import SwiftUI

/// What a drag in the plot area does.
public enum PlotMode: Equatable, Sendable {
    case zoomBox, pan, measure
}

/// The toolbar of the plot, a fixed strip above it as in Finder or Preview: the mode of the drag, then the zoom, the autoscale
/// and the return to the whole signal.
struct PlotToolbar: View {
    @Binding var mode: PlotMode
    var labels: PlotLabels
    var accent: Color
    @State private var showsHelp = false
    var zoomIn: () -> Void
    var zoomOut: () -> Void
    var autoscale: () -> Void
    var reset: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // The modes are one control: only one is on.
            HStack(spacing: 1) {
                modeButton(.zoomBox, "rectangle.dashed", labels.zoomBox)
                modeButton(.pan, "hand.draw", labels.pan)
                modeButton(.measure, "ruler", labels.measure)
            }
            .padding(2)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
            HStack(spacing: 2) {
                action("plus.magnifyingglass", labels.zoomIn + " (" + labels.zoomModifiers + ")", zoomIn)
                action("minus.magnifyingglass", labels.zoomOut + " (" + labels.zoomModifiers + ")", zoomOut)
            }
            HStack(spacing: 2) {
                action("arrow.up.and.down", labels.autoscale, autoscale)
                action("arrow.up.left.and.down.right.magnifyingglass", labels.reset, reset)
            }
            Spacer(minLength: 0)
            Button { showsHelp.toggle() } label: {
                Image(systemName: "questionmark.circle").font(.system(size: 14)).frame(width: 28, height: 24)
                    .foregroundStyle(Color.primary.opacity(0.7)).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help(labels.gesturesTitle)
            .popover(isPresented: $showsHelp, arrowEdge: .bottom) { PlotGesturesHelp(title: labels.gesturesTitle, sections: labels.gestures) }
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(Color.primary.opacity(0.04))
        .overlay(alignment: .bottom) { Divider() }
    }

    private func modeButton(_ value: PlotMode, _ symbol: String, _ help: String) -> some View {
        Button { mode = value } label: {
            Image(systemName: symbol).font(.system(size: 13)).frame(width: 30, height: 24)
                .foregroundStyle(mode == value ? Color.white : Color.primary.opacity(0.85))
                .background(mode == value ? accent : .clear, in: RoundedRectangle(cornerRadius: 5.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help)
    }

    private func action(_ symbol: String, _ help: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: symbol).font(.system(size: 13)).frame(width: 30, height: 24)
                .foregroundStyle(Color.primary.opacity(0.85)).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help)
    }
}
