import Foundation

enum ModerationActionType: String, Codable {
    case ocultar
    case restablecer
}

struct NewModerationAction: Encodable {
    var activityId: UUID
    var adminId: UUID
    var action: ModerationActionType
}
