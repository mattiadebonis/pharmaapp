import Foundation

public enum EventType: String, Codable {
    case intakeRecorded = "intake_recorded"
    case intakeUndone = "intake_undone"
    case purchaseRecorded = "purchase_recorded"
    case purchaseUndone = "purchase_undone"
    case prescriptionRequested = "prescription_requested"
    case prescriptionRequestUndone = "prescription_request_undone"
    case prescriptionReceived = "prescription_received"
    case prescriptionReceivedUndone = "prescription_received_undone"
    case stockAdjusted = "stock_adjusted"
}
