//  CouncilKit.swift
//  Package-level identity for the engine: version + attribution. The app and the `council` CLI are
//  thin shells over this package, so they read their signature from here rather than hardcoding it.
//  Caseless-enum namespace, mirroring the `CouncilLimits` pattern (CouncilStore.swift).

import Foundation

/// Engine identity. Surfaced verbatim by the thin shells: the app's Settings footer and the CLI's
/// `--version` / `--help` banner.
public enum CouncilKit {
    /// Engine version, kept in step with the Council release line (app MARKETING_VERSION).
    public static let version = "1.1.2"

    /// Maintainer of CouncilKit and the Council app.
    public static let author = "Joseph"

    /// Short one-line signature for footers and version output.
    public static let signature = "Powered by CouncilKit"

    /// Full attribution line: signature + copyright.
    public static let attribution = "\(signature) · © 2026 \(author)"
}
