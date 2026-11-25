// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import JConvolverKit
import SwiftUI

extension AppModel {
    /// The rate that the impulse responses must have: the one of the JACK server in real time, the one of the input file on sound files.
    var expectedRate: Double? {
        if mode == .realTime { return jack.sampleRate.map(Double.init) }
        return inputFile.flatMap { catalog.info(at: $0.path)?.sampleRate }
    }

    /// Brings a sound file of the matrix to the expected rate: a new file next to it (the original is left alone, and an earlier conversion that is
    /// strictly the same is used instead of a new file), and every impulse response of the matrix that uses the original uses it. One step of the
    /// history, which undoes the change in the matrix (the new file stays).
    func convertToExpectedRate(path: String) {
        guard let rate = expectedRate, conversionName == nil, !isLocked else { return }
        let source = URL(fileURLWithPath: path)
        conversionName = source.lastPathComponent
        Task {
            var outcome = await Self.convert(source: source, rate: rate, folder: nil)
            // A folder where nothing can be written (a read-only volume): another one is asked for.
            if case .failure(let error) = outcome, case AudioResamplerError.cannotWrite = error, let folder = chooseFolder(for: source) {
                outcome = await Self.convert(source: source, rate: rate, folder: folder)
            }
            conversionName = nil
            switch outcome {
            case .success(let result): finishConversion(result, of: path, rate: rate)
            case .failure(let error): message = Self.describe(error, file: source.lastPathComponent)
            }
        }
    }

    private nonisolated static func convert(source: URL, rate: Double, folder: URL?) async -> Result<ResampleResult, Error> {
        await Task.detached(priority: .userInitiated) { Result { try AudioResampler.resample(source: source, toRate: rate, in: folder) } }.value
    }

    private func chooseFolder(for source: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Le dossier de « \(source.lastPathComponent) » n'est pas accessible en écriture : choisissez où écrire le fichier converti.")
        panel.prompt = String(localized: "Choisir")
        return panel.runModal() == .OK ? panel.url : nil
    }

    private static func describe(_ error: Error, file: String) -> String {
        switch error as? AudioResamplerError {
        case .alreadyAtRate?: return String(localized: "« \(file) » est déjà à la fréquence attendue.")
        case .tooLarge?: return String(localized: "« \(file) » est trop gros pour être converti ici.")
        case .cannotRead(let why)?: return String(localized: "« \(file) » ne peut pas être lu : \(why)")
        case .conversionFailed(let why)?: return String(localized: "La conversion de « \(file) » a échoué : \(why)")
        case .cannotWrite(let why)?: return String(localized: "Le fichier converti ne peut pas être écrit : \(why)")
        case nil: return error.localizedDescription
        }
    }

    /// Puts the converted file in the place of the original in every impulse response that uses it, and says what was done.
    private func finishConversion(_ result: ResampleResult, of path: String, rate: Double) {
        let configDirectory = self.configDirectory
        let newName = result.url.lastPathComponent
        let originalRate = catalog.info(at: path)?.sampleRate ?? rate
        let ratio = originalRate > 0 ? rate / originalRate : 1
        let sameFolder = result.url.deletingLastPathComponent().standardizedFileURL == URL(fileURLWithPath: path).deletingLastPathComponent().standardizedFileURL
        var count = 0
        var compared: (target: DetailTarget, reference: ReferenceTrace)?
        func hz(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0...1))) }
        let label = String(localized: "conversion à \(Int(rate.rounded())) Hz")
        edit(label) { document in
            for pair in document.content.impulses.keys.sorted() {
                for (index, impulse) in document.impulses(at: pair).enumerated() {
                    guard case .file(let file, let channel) = impulse.source,
                          ConvConfig.path(of: file, directory: impulse.directory, configDirectory: configDirectory) == path else { continue }
                    // The name keeps the way it was written: a path stays a path, a name next to the configuration stays a name.
                    let replacement: String
                    if file.hasPrefix("/") || !sameFolder { replacement = result.url.path }
                    else { replacement = ((file as NSString).deletingLastPathComponent as NSString).appendingPathComponent(newName) }
                    var changed = impulse
                    changed.source = .file(path: replacement, channel: channel)
                    // The start and the length are in frames of the file: the same part of it is the same time in the new frames. The delay is in
                    // frames of the engine, which do not change.
                    changed.offset = Int((Double(impulse.offset) * ratio).rounded())
                    changed.length = impulse.length > 0 ? max(1, Int((Double(impulse.length) * ratio).rounded())) : 0
                    document.replace(changed, at: index, of: pair)
                    if compared == nil {
                        compared = (DetailTarget(pair: pair, index: index),
                                    ReferenceTrace(path: path, channel: channel, offset: impulse.offset, length: impulse.length,
                                                   name: String(localized: "Original · \(hz(originalRate / 1000)) kHz")))
                    }
                    count += 1
                }
            }
        }
        loadBin()
        let used = count == 1 ? String(localized: "1 réponse impulsionnelle utilise maintenant") : String(localized: "\(count) réponses impulsionnelles utilisent maintenant")
        let alert = NSAlert()
        alert.messageText = result.reused
            ? String(localized: "Ce fichier était déjà converti.")
            : String(localized: "Fichier converti à \(hz(rate)) Hz.")
        alert.informativeText = String(localized: "\(used) « \(newName) ». L'original est intact. Le début et la longueur de chaque réponse ont été recalculés pour la nouvelle fréquence, et le gain des coefficients compensé pour que la réponse en fréquence ne change pas.")
        if compared != nil { alert.addButton(withTitle: String(localized: "Comparer avec l'original")) }
        alert.addButton(withTitle: "OK")
        let answer: NSApplication.ModalResponse
        #if DEBUG
        // Debug aid: with JACKCONVOLVER_CONVERT the alert is not shown and the comparison is chosen (for the screenshots).
        if ProcessInfo.processInfo.environment["JACKCONVOLVER_CONVERT"] != nil { answer = .alertFirstButtonReturn } else { answer = alert.runModal() }
        #else
        answer = alert.runModal()
        #endif
        if answer == .alertFirstButtonReturn, let compared {
            compare(compared.target, with: compared.reference)
            // While it is looked at, the conversion can be kept or refused.
            pendingConversion = PendingConversion(label: label, convertedURL: result.url, created: !result.reused, rate: rate)
        }
    }

    /// The conversion is not good enough: the matrix goes back to the original (the step of the history is undone) and the file that the conversion
    /// wrote goes to the Trash (not one that was already there). The analysis is closed.
    func refuseConversion() {
        guard let pending = pendingConversion, undoLast(labelled: pending.label) else {
            message = String(localized: "La conversion ne peut plus être refusée d'un coup : annulez-la à la main avec ⌘Z.")
            return
        }
        var trashed = false
        if pending.created { trashed = (try? FileManager.default.trashItem(at: pending.convertedURL, resultingItemURL: nil)) != nil }
        loadBin()
        closeAnalysis()
        message = trashed
            ? String(localized: "Conversion refusée : la matrice est revenue à l'original, et « \(pending.convertedURL.lastPathComponent) » est à la corbeille.")
            : String(localized: "Conversion refusée : la matrice est revenue à l'original.")
    }

    /// The conversion is kept: the comparison is closed.
    func keepConversion() { closeAnalysis() }
}

/// A conversion looked at against its original: what to undo if it is refused.
struct PendingConversion: Equatable {
    /// The label of its step in the history.
    let label: String
    let convertedURL: URL
    /// Whether the conversion wrote that file (a file that was there already is not thrown away).
    let created: Bool
    let rate: Double
}
