import CoreHaptics
import UIKit

/// Haptik wie in der TESS App (Ole, 01.11.2026: „ich liebe die Haptik“). Gleiche Muster, gleiche Namen, Quelle
/// TESS_APP/TESS/App/Haptics.swift. Dazu zwei für den Player: Marke überfahren und Video gewechselt.
@MainActor
enum Haptics {
    private static let engine: CHHapticEngine? = {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics, let engine = try? CHHapticEngine() else { return nil }
        engine.isAutoShutdownEnabled = true
        engine.resetHandler = { [weak engine] in try? engine?.start() }
        return engine
    }()

    /// Knöpfe, Schalter, Menüs: kurzer, leichter Tick
    static func select() {
        play([tick(0, 0.5, 0.7)]) { UISelectionFeedbackGenerator().selectionChanged() }
    }

    /// Antippen von etwas Großem (Video, Karte): kräftiger, trockener Klick
    static func press() {
        play([tick(0, 1.0, 0.75)]) { UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 1) }
    }

    /// Gesendet: zweimal kurz, wie Abschicken
    static func sent() {
        play([tick(0, 0.9, 0.6), tick(0.08, 0.5, 0.35)]) { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    }

    /// Abgehakt (Kommentar erledigt, freigegeben): knackiger Klick, dann kurzes Nachfedern
    static func check() {
        play([tick(0, 0.85, 0.9), tick(0.06, 0.35, 0.5)]) {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.8)
        }
    }

    /// Fertig (Link ist live, gespeichert): weiches Doppeltippen wie „Antwort da“ in der TESS App
    static func done() {
        play([tick(0, 0.45, 0.2), tick(0.12, 0.7, 0.3)]) { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }

    /// Abbrechen, Löschen: kurzer Tipp, der schnell ausklingt
    static func cancel() {
        let fade = CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.1),
        ], relativeTime: 0.04, duration: 0.26)
        let out = CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
            .init(relativeTime: 0, value: 1.0),
            .init(relativeTime: 0.26, value: 0.0),
        ], relativeTime: 0.04)
        play([tick(0, 0.55, 0.3), fade], curves: [out]) { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    }

    /// Video gewechselt: kurzes Wischen von hell nach weich plus sauberer Klick (wie „Neue Session“ in der TESS App, kürzer)
    static func swap() {
        let sweep = CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.45),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5),
        ], relativeTime: 0, duration: 0.1)
        play([sweep, tick(0.12, 0.6, 0.7)]) { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    }

    /// Beim Spulen über eine Kommentar Marke: ganz leichter Tick
    static func marker() {
        play([tick(0, 0.35, 0.9)]) { UISelectionFeedbackGenerator().selectionChanged() }
    }

    /// Fehler: wie iOS
    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    private static func tick(_ time: TimeInterval, _ intensity: Float, _ sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
        ], relativeTime: time)
    }

    private static func play(_ events: [CHHapticEvent], curves: [CHHapticParameterCurve] = [], fallback: () -> Void) {
        guard let engine else { return fallback() }
        do {
            try engine.start()
            let pattern = try CHHapticPattern(events: events, parameterCurves: curves)
            try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
        } catch {
            fallback()
        }
    }
}
