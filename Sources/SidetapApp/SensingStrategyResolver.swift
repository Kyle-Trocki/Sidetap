import SidetapCore

/// Resolves which sensing strategy the audio engine should run, in priority
/// order: the calibration draft, then the selected profile.
enum SensingStrategyResolver {
    static func resolve(
        calibration: SensingStrategy?,
        profile: SensingStrategy?
    ) -> SensingStrategy {
        calibration ?? profile ?? .passive
    }
}
