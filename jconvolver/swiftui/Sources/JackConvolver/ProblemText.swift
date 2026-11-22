// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import JConvolverKit
import SoundFileKit

/// What the matrix and the engine say, in the language of the person. The library describes them without words.
extension ConvProblem {
    /// Where it is, in a few words.
    var place: String {
        if let pair { return String(localized: "Entrée \(pair.input + 1) → sortie \(pair.output + 1)") }
        switch kind {
        case .jackNotRunning: return "JACK"
        case .inputFileChannels: return String(localized: "Fichier d'entrée")
        case .latencyAffects: return String(localized: "Options de lancement")
        case .tooManyPorts, .emptyPortName, .duplicatePortName, .sharedPortName: return String(localized: "Noms des ports JACK")
        case .noImpulse: return String(localized: "Matrice")
        case .partitionIllegal, .maxLengthOutOfRange, .maxLengthTooShort, .densityOutOfRange: return String(localized: "Fichier de configuration")
        default: return String(localized: "Matrice")
        }
    }

    var message: String {
        func name(_ path: String) -> String { (path as NSString).lastPathComponent }
        func hz(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0...1))) }
        func port(_ isInput: Bool, _ index: Int) -> String { isInput ? String(localized: "L'entrée \(index + 1)") : String(localized: "La sortie \(index + 1)") }
        switch kind {
        case .jackNotRunning:
            return String(localized: "JACK n'est pas lancé : la fréquence et la période ne peuvent pas être vérifiées.")
        case .inputFileChannels(let channels, let expected):
            return String(localized: "Le fichier d'entrée a \(channels) voie(s) ; la configuration compte \(expected) entrée(s). fconvolver exige le même nombre.")
        case .latencyAffects(let count):
            return String(localized: "La compensation de latence supprime ou raccourcit \(count) RI.")
        case .latencyBeyondFile(let path, let frames, let removed):
            return String(localized: "La compensation de latence retire \(removed) échantillons au début de « \(name(path)) », qui n'en a que \(frames) : cette RI restera muette. Donnez-lui un retard, ou baissez la compensation.")
        case .tooManyPorts(let inputs, let outputs, let maximum):
            return String(localized: "\(inputs) entrées et \(outputs) sorties : au plus \(maximum).")
        case .emptyPortName(let isInput, let index):
            return String(localized: "\(port(isInput, index)) n'a pas de nom.")
        case .duplicatePortName(let isInput, let n, let count):
            return isInput ? String(localized: "\(count) entrées portent le nom « \(n) ».") : String(localized: "\(count) sorties portent le nom « \(n) ».")
        case .sharedPortName(let n):
            return String(localized: "« \(n) » est le nom d'une entrée et d'une sortie : les ports d'un client JACK ont des noms uniques.")
        case .noImpulse:
            return String(localized: "Aucune RI : glissez des fichiers sur les cases.")
        case .fileMissing(let path):
            return String(localized: "« \(name(path)) » est introuvable dans \((path as NSString).deletingLastPathComponent).")
        case .sampleRateMismatch(let path, let fileRate, let expected):
            return String(localized: "« \(name(path)) » est à \(hz(fileRate)) Hz, le serveur JACK est à \(hz(expected)) Hz.")
        case .startBeyondEnd(let offset, let frames):
            return String(localized: "Le début (\(offset)) dépasse la fin du fichier (\(frames) échantillons).")
        case .channelMissing(let channel, let channels):
            return String(localized: "Le fichier n'a que \(channels) voie(s) : la voie \(channel) n'existe pas.")
        case .hilbertLengthOutOfRange(let length):
            return String(localized: "La longueur d'un filtre de Hilbert va de 64 à 65 536 (ici \(length)).")
        case .hilbertDelayTooSmall(let delay, let minimum):
            return String(localized: "Le retard (\(delay)) doit être au moins \(minimum) pour ce filtre de Hilbert.")
        case .copyOfEmptyPair(let source):
            return String(localized: "Copie de l'entrée \(source.input + 1) → sortie \(source.output + 1), où rien n'est placé.")
        case .partitionIllegal(let p):
            return String(localized: "La partition (\(p)) doit être une puissance de 2 de 64 à 8 192.")
        case .maxLengthOutOfRange(let m):
            return String(localized: "La longueur maximale (\(m)) dépasse 1 048 576.")
        case .maxLengthTooShort(let m, let needed):
            return String(localized: "La longueur maximale (\(m)) est plus courte que la plus longue RI (\(needed)) : elle sera tronquée.")
        case .densityOutOfRange(let d):
            return String(localized: "La densité (\(d.formatted())) doit être entre 0 et 1.")
        }
    }
}

/// A line of the journal, in the language of the person: the notes of the application and of JACK are written here; the lines
/// of the program stay as the program wrote them.
extension EngineLogEntry {
    var display: String {
        guard let note else { return text }
        switch note {
        case .launch(let line): return String(localized: "Lancement : \(line)")
        case .cannotLaunch(let reason): return String(localized: "Le programme ne peut pas démarrer : \(reason)")
        case .stopRequested: return String(localized: "Arrêt demandé (SIGINT)")
        case .ended(let program, let status): return String(localized: "\(program) terminé (code \(status))")
        case .xrun(let us): return us.map { String(localized: "xrun : \($0) µs de retard") } ?? String(localized: "xrun")
        case .fileWritten(let name): return String(localized: "Fichier écrit : \(name)")
        }
    }
}
