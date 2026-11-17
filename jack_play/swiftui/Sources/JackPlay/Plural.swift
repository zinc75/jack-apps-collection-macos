// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// The texts that depend on a number. The source language is French, where one and zero are singular, but the catalog has a key
/// for one and a key for the others, as the other applications of the collection: the translations pick the right form.
enum Plural {
    static func channels(_ n: Int) -> LocalizedStringKey {
        n == 1 ? "1 voie" : "\(n) voies"
    }

    static func silentChannels(_ n: Int) -> LocalizedStringKey {
        n == 1 ? "1 voie sans sortie" : "\(n) voies sans sortie"
    }

    static func files(_ n: Int) -> LocalizedStringKey {
        n == 1 ? "1 fichier" : "\(n) fichiers"
    }

    static func inputs(_ n: Int) -> LocalizedStringKey {
        n == 1 ? "1 entrée" : "\(n) entrées"
    }

    static func fileAndChannels(_ name: String, _ n: Int) -> LocalizedStringKey {
        n == 1 ? "Fichier : \(name) · 1 voie" : "Fichier : \(name) · \(n) voies"
    }

    /// How many channels of the file are connected: all of them, or `used` of `n`.
    static func connected(used: Int, of n: Int) -> LocalizedStringKey {
        if used == n { return n == 1 ? "La voie est reliée. " : "Toutes les voies sont reliées. " }
        return used == 1 ? "1 voie sur \(n) reliée : les autres restent sans sortie. " : "\(used) voies sur \(n) reliées : les autres restent sans sortie. "
    }
}
