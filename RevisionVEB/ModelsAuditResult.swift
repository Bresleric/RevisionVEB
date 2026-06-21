//
//  AuditResult.swift
//  RevisionVEB
//
//  Created by eric bresler on 19/06/2026.
//

import Foundation
import SwiftData

@Model
final class AuditResult {
    var id: UUID
    var ruleId: String
    var ruleName: String
    var invoiceId: UUID?
    var invoiceNumber: String
    var status: AuditStatus
    var details: String
    var variance: Double
    var timestamp: Date
    var cycle: AuditCycle
    var severity: Severity
    
    init(
        id: UUID = UUID(),
        ruleId: String,
        ruleName: String,
        invoiceId: UUID? = nil,
        invoiceNumber: String,
        status: AuditStatus,
        details: String,
        variance: Double = 0.0,
        timestamp: Date = Date(),
        cycle: AuditCycle,
        severity: Severity = .info
    ) {
        self.id = id
        self.ruleId = ruleId
        self.ruleName = ruleName
        self.invoiceId = invoiceId
        self.invoiceNumber = invoiceNumber
        self.status = status
        self.details = details
        self.variance = variance
        self.timestamp = timestamp
        self.cycle = cycle
        self.severity = severity
    }
}

enum AuditStatus: String, Codable, CaseIterable {
    case passed = "✅ Conforme"
    case warning = "⚠️ Alerte"
    case failed = "❌ Anomalie"
    
    var color: String {
        switch self {
        case .passed: return "green"
        case .warning: return "orange"
        case .failed: return "red"
        }
    }
}

enum Severity: String, Codable, CaseIterable {
    case info = "Info"
    case warning = "Avertissement"
    case critical = "Critique"
}
