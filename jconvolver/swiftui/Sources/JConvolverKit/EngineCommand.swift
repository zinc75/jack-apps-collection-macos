// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The command line of jconvolver (real time, with JACK) or fconvolver (on sound files).
public struct EngineCommand: Equatable, Sendable {
    public enum Program: String, Sendable, CaseIterable {
        case jconvolver
        case fconvolver
    }

    /// The options of the programs. Those that a program does not have are left out of its command line.
    public struct Options: Equatable, Sendable {
        /// `-V`: processes four frequencies at a time with vector instructions. Both programs.
        public var vectorMode = false
        /// `-M`: lets FFTW measure to choose its algorithms at the start. Both programs.
        public var measure = false
        /// `-Z`: adds an inaudible noise against denormal numbers. jconvolver only.
        public var denormalProtection = false
        /// `-L n`: moves the impulse responses `n` samples earlier, to make up for a delay added elsewhere; 0 for none.
        /// jconvolver only.
        public var latencyCompensation = 0
        /// `-T`: cuts the output to the length of the input, without the tail. fconvolver only.
        public var truncate = false

        public init() {}
    }

    public var program: Program
    public var options: Options
    /// The configuration file.
    public var configPath: String
    /// `-N`: the name of the JACK client, which takes the place of the one of the file. jconvolver only.
    public var clientName: String?
    /// `-s`: the JACK server. jconvolver only.
    public var serverName: String?
    /// The sound files to process. fconvolver only.
    public var inputFile: String?
    public var outputFile: String?

    public init(program: Program, options: Options = Options(), configPath: String, clientName: String? = nil,
                serverName: String? = nil, inputFile: String? = nil, outputFile: String? = nil) {
        self.program = program
        self.options = options
        self.configPath = configPath
        self.clientName = clientName
        self.serverName = serverName
        self.inputFile = inputFile
        self.outputFile = outputFile
    }

    /// The arguments, one by one (not including the name of the program).
    public var arguments: [String] {
        var a: [String] = []
        if options.vectorMode { a.append("-V") }
        if options.measure { a.append("-M") }
        switch program {
        case .jconvolver:
            if options.denormalProtection { a.append("-Z") }
            if options.latencyCompensation > 0 { a += ["-L", String(options.latencyCompensation)] }
            if let clientName, !clientName.isEmpty { a += ["-N", clientName] }
            if let serverName, !serverName.isEmpty { a += ["-s", serverName] }
            a.append(configPath)
        case .fconvolver:
            if options.truncate { a.append("-T") }
            a.append(configPath)
            a.append(inputFile ?? "")
            a.append(outputFile ?? "")
        }
        return a
    }

    /// The command line as one would type it in a terminal, to read or to copy.
    public var displayString: String {
        ([program.rawValue] + arguments).map(Self.shellQuote).joined(separator: " ")
    }

    /// Between single quotes when it must be.
    static func shellQuote(_ word: String) -> String {
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_@%+=:,./-")
        if !word.isEmpty, word.unicodeScalars.allSatisfy({ safe.contains($0) }) { return word }
        return "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// Where the programs are. The application runs the copies it carries in `Contents/Helpers`: the ones that were built and
/// tested with it, whatever is installed elsewhere. Only development builds look further.
public enum EngineHelper {
    public static func executableURL(for program: EngineCommand.Program, bundle: Bundle = .main,
                                     environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        var candidates = [bundle.bundleURL.appendingPathComponent("Contents/Helpers/\(program.rawValue)").path]
        #if DEBUG
        if let directory = environment["JCONVOLVER_BIN_DIR"] { candidates.insert(directory + "/" + program.rawValue, at: 0) }
        candidates += ["/usr/local/bin/\(program.rawValue)", "/opt/homebrew/bin/\(program.rawValue)"]
        #endif
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }
}
