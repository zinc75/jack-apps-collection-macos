// SPDX-License-Identifier: GPL-3.0-or-later

import PlotKit

extension PlotLabels {
    /// The texts of the plots in the language of the application (the keys are the French texts, as everywhere else).
    static var localized: PlotLabels {
        var l = PlotLabels()
        l.zoomBox = String(localized: "Zoom sur une zone")
        l.pan = String(localized: "Déplacer")
        l.measure = String(localized: "Mesurer")
        l.zoomIn = String(localized: "Agrandir")
        l.zoomOut = String(localized: "Réduire")
        l.zoomModifiers = String(localized: "⌥-clic : axe vertical, ⇧-clic : les deux axes")
        l.autoscale = String(localized: "Ajuster l'axe vertical")
        l.reset = String(localized: "Tout voir")
        l.samples = String(localized: "échantillons")
        l.inspector = String(localized: "Inspecteur")
        l.display = String(localized: "Affichage")
        l.phase = String(localized: "Phase")
        l.fill = String(localized: "Remplissage")
        l.phaseCurve = String(localized: "Courbe de phase")
        l.smoothingBand = String(localized: "Bande")
        l.moreDetails = String(localized: "Plus de détails")
        l.groupDelay = String(localized: "Retard de groupe")
        l.groupDelayHelp = String(localized: "Montre le retard de groupe en millisecondes, calculé à partir de la réponse impulsionnelle, à la place de la phase.")
        l.smoothing = String(localized: "Lissage")
        l.noSmoothing = String(localized: "Aucun")
        l.showUnsmoothed = String(localized: "Montrer la courbe brute")
        l.smoothingHelp = String(localized: "Moyenne la puissance dans une bande d'une fraction d'octave autour de chaque fréquence : ce qu'on lit est l'énergie par bande.")
        l.removeDelay = String(localized: "Retirer le retard")
        l.delayFitted = String(localized: "ajusté")
        l.delayGiven = String(localized: "son direct")
        l.removeDelayHelp = String(localized: "Retire de la phase le retard (la droite qu'elle dessine) : ce qui reste est la phase du système lui-même.")
        l.unwrapPhase = String(localized: "Dérouler la phase")
        l.unwrapPhaseHelp = String(localized: "Ajoute des tours entiers pour que la phase soit continue, sans les sauts entre −180° et +180°.")
        l.gradientUnderCurve = String(localized: "Dégradé sous la courbe")
        l.gradientWithSeveral = String(localized: "Aussi avec plusieurs courbes")
        l.gradientHelp = String(localized: "Désactivé, le remplissage est uni. Avec plusieurs courbes il est opaque : celle du dessus cache celles du dessous.")
        l.channels = String(localized: "Voies")
        l.allChannels = String(localized: "Toutes")
        l.noChannels = String(localized: "Aucune")
        l.onlyChannel = String(localized: "Seule")
        l.toFront = String(localized: "Mettre au premier plan")
        l.channelsHelp = String(localized: "Glisser pour réordonner. La première est dessinée au-dessus des autres.")
        l.xAxis = String(localized: "Axe horizontal")
        l.yAxis = String(localized: "Axe vertical")
        l.linear = String(localized: "Linéaire")
        l.logarithmic = String(localized: "Logarithmique")
        l.decibels = String(localized: "Décibels")
        l.gesturesTitle = String(localized: "Gestes du tracé")
        l.gestures = [
            PlotGestureSection(String(localized: "Zoom"), [
                PlotGestureItem(String(localized: "Pincement"), String(localized: "Zoom sur l'axe horizontal autour du pointeur")),
                PlotGestureItem(String(localized: "⌥ Pincement"), String(localized: "Zoom sur l'axe vertical")),
                PlotGestureItem(String(localized: "⇧ Pincement"), String(localized: "Zoom sur les deux axes")),
                PlotGestureItem(String(localized: "Molette"), String(localized: "Comme le pincement (⌥ vertical, ⇧ les deux)")),
                PlotGestureItem(String(localized: "⌘ Défilement"), String(localized: "Pareil, au pavé tactile ou à la Magic Mouse")),
                PlotGestureItem(String(localized: "Boutons de zoom"), String(localized: "Pareil, autour du centre (⌥-clic vertical, ⇧-clic les deux)")),
            ]),
            PlotGestureSection(String(localized: "Déplacement"), [
                PlotGestureItem(String(localized: "Défilement"), String(localized: "Fait glisser la vue (pavé tactile, Magic Mouse)")),
                PlotGestureItem(String(localized: "Glisser, en mode Déplacer"), String(localized: "Fait glisser la vue")),
                PlotGestureItem(String(localized: "⇧ Glisser"), String(localized: "Fait glisser la vue, quel que soit le mode")),
            ]),
            PlotGestureSection(String(localized: "Zone et axes"), [
                PlotGestureItem(String(localized: "Glisser, en mode Zoom"), String(localized: "Trace une zone et zoome dessus")),
                PlotGestureItem(String(localized: "Glisser sur un axe"), String(localized: "Le milieu le fait glisser, une extrémité change l'échelle (l'autre reste)")),
                PlotGestureItem(String(localized: "Double clic dans le tracé"), String(localized: "Montre tout")),
                PlotGestureItem(String(localized: "Double clic sur un axe"), String(localized: "Horizontal : tout montrer. Vertical : ajuster à ce qui est visible")),
            ]),
            PlotGestureSection(String(localized: "Mesure"), [
                PlotGestureItem(String(localized: "Pointeur sur le tracé"), String(localized: "Réticule avec les valeurs, sur l'échantillon le plus proche quand on peut les distinguer")),
                PlotGestureItem(String(localized: "Glisser, en mode Mesurer"), String(localized: "Temps, fréquence (1/Δt) et niveau entre deux points")),
            ]),
        ]
        return l
    }
}
