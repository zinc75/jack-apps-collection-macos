// SPDX-License-Identifier: MIT

import Foundation

/// A connection from an output port to an input port, as `"client:port"`.
public struct JackLink: Hashable, Sendable {
    public let output: String
    public let input: String
    public init(output: String, input: String) { self.output = output; self.input = input }
}

/// What the reconciler needs from the JACK server. The real one is the graph of the application; the tests give a fake.
@MainActor
public protocol JackLinking: AnyObject {
    /// The audio output ports of the graph now, as `"client:port"`.
    func outputPorts() -> Set<String>
    /// The audio input ports of the graph now.
    func inputPorts() -> Set<String>
    /// The ports an output is connected to now.
    func destinations(of output: String) -> Set<String>
    func connect(from output: String, to input: String) throws
    func disconnect(from output: String, to input: String) throws
    /// Every connection of the audio ports of the graph now. The default asks each output; an implementation that reads the graph at once should give it.
    func allLinks() -> Set<JackLink>
}

extension JackLinking {
    public func allLinks() -> Set<JackLink> {
        var links = Set<JackLink>()
        for output in outputPorts() { for input in destinations(of: output) { links.insert(JackLink(output: output, input: input)) } }
        return links
    }
}

/// Keeps the connections of a program as an application wants them. The application says which links it wants; the
/// reconciler makes them, as far as the graph allows, and again each time it is asked.
///
/// The ports of a program that has just been started appear a moment after it, and the other clients may not be running
/// yet: what cannot be connected now is remembered, and made when the port appears. A connection that went with a port
/// that left is made again when the port returns. A connection that is already there (made by a previous run, or by another
/// tool) is not made twice, and is the reconciler's to remove when the application no longer wants it.
@MainActor
public final class ConnectionReconciler {
    /// Which end of the links belongs to the program of the application.
    public enum OwnEnd: Sendable {
        /// The program's outputs are wired to the inputs of other clients.
        case output
        /// The program's inputs are fed by the outputs of other clients.
        case input
    }

    /// Ports of the other clients that the wanted links name and that are not in the graph. The program's own port is not
    /// counted: it is not there yet when the program has just started.
    public private(set) var missingPorts: Set<String> = []
    /// Connections that JACK refused for another reason than a missing port, written for a person ("a:out_1 → b:in").
    public private(set) var failures: [String] = []

    private let linking: JackLinking
    private let own: OwnEnd
    private let checksOwnPorts: Bool
    private var applied: Set<JackLink> = []

    /// - Parameter checksOwnPorts: whether a link is left alone while the program's own port is not in the graph (the
    ///   default: a program that has just started registers its ports a moment later). A caller that only asks once the
    ///   program says its ports exist can turn it off.
    public init(linking: JackLinking, own: OwnEnd, checksOwnPorts: Bool = true) {
        self.linking = linking
        self.own = own
        self.checksOwnPorts = checksOwnPorts
    }

    /// Makes the wanted links and removes those that were made and are no longer wanted.
    public func reconcile(wanted: Set<JackLink>) {
        let outputs = linking.outputPorts(), inputs = linking.inputPorts()
        // Is a port in the graph? The program's own ports count as there when they are not checked.
        func isThere(output: String) -> Bool { (own == .output && !checksOwnPorts) || outputs.contains(output) }
        func isThere(input: String) -> Bool { (own == .input && !checksOwnPorts) || inputs.contains(input) }
        for link in applied.subtracting(wanted) {
            try? linking.disconnect(from: link.output, to: link.input)
            applied.remove(link)
        }
        var missing = Set<String>(), failed = [String]()
        for link in wanted {
            let outputThere = isThere(output: link.output), inputThere = isThere(input: link.input)
            guard outputThere, inputThere else {
                let other = own == .output ? link.input : link.output
                if !(own == .output ? inputThere : outputThere) { missing.insert(other) }
                continue
            }
            if applied.contains(link) { continue }
            if linking.destinations(of: link.output).contains(link.input) { applied.insert(link); continue }
            do {
                try linking.connect(from: link.output, to: link.input)
                applied.insert(link)
            } catch {
                failed.append("\(link.output) → \(link.input)")
            }
        }
        // A connection that was made and is gone because a port left is made again when it returns.
        applied = applied.filter { isThere(output: $0.output) && isThere(input: $0.input) }
        missingPorts = missing
        failures = failed
    }

    // MARK: What is really there

    /// The connections of the program's own ports as they are in the graph now, whoever made them (this application, JackMate, a patchbay).
    public func actualLinks(ownClient: String) -> Set<JackLink> {
        let prefix = ownClient + ":"
        return linking.allLinks().filter { own == .output ? $0.output.hasPrefix(prefix) : $0.input.hasPrefix(prefix) }
    }

    /// What the wanted links become when the graph has been changed by someone else: **the reality is adopted** (a connection made elsewhere is wanted
    /// from now on, one removed elsewhere is no longer wanted). A link whose port is not in the graph (a device that is unplugged, an application that is
    /// not running, an own port not registered yet) keeps its place: it is made when the port comes.
    public func adopted(wanted: Set<JackLink>, ownClient: String) -> Set<JackLink> {
        let actual = actualLinks(ownClient: ownClient)
        let outputs = linking.outputPorts(), inputs = linking.inputPorts()
        var result = actual
        for link in wanted where !actual.contains(link) && !(outputs.contains(link.output) && inputs.contains(link.input)) { result.insert(link) }
        return result
    }

    /// The program has ended (its connections went with it), or starts again: forgets what was made.
    public func reset() {
        applied = []
        missingPorts = []
        failures = []
    }
}

/// A JACK client with audio ports of one kind: somewhere an application can wire to, or something it can take from.
public struct JackPortClient: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public let name: String
    /// Port names without the client part, in the order JACK lists them.
    public var ports: [String]
    /// The sound card ("system": its inputs are the playback ports, its outputs the capture ports).
    public let isSystem: Bool
    /// Bundle identifier of the application a JackMoebius box stands for, if any.
    public var bundleID: String?
    /// The system node of JackMoebius, whose shared inputs get the picto of JackMoebius.
    public var isJackMoebiusMaster: Bool

    public init(name: String, ports: [String], isSystem: Bool, bundleID: String? = nil, isJackMoebiusMaster: Bool = false) {
        self.name = name
        self.ports = ports
        self.isSystem = isSystem
        self.bundleID = bundleID
        self.isJackMoebiusMaster = isJackMoebiusMaster
    }

    public func fullName(of port: String) -> String { "\(name):\(port)" }

    /// Groups ports (`"client:port"`) by client. The sound card comes first, the others by name.
    public static func group(ports full: [String]) -> [JackPortClient] {
        var order: [String] = []
        var ports: [String: [String]] = [:]
        for name in full {
            guard let colon = name.firstIndex(of: ":") else { continue }
            let client = String(name[..<colon]), port = String(name[name.index(after: colon)...])
            if ports[client] == nil { order.append(client) }
            ports[client, default: []].append(port)
        }
        return order.map { JackPortClient(name: $0, ports: ports[$0] ?? [], isSystem: $0 == "system") }.sorted {
            if $0.isSystem != $1.isSystem { return $0.isSystem }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
