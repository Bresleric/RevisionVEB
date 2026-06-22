//
//  ImportLog.swift
//  RevisionVEB
//
//  Created by eric bresler on 19/06/2026.
//

import Foundation
import SwiftData

@Model
final class ImportLog {
    var id: UUID
    var fileName: String
    var fileType: FileType
    var status: ImportStatus
    var recordsCount: Int
    var successCount: Int
    var errorCount: Int
    var timestamp: Date
    var errorDetails: String
    var restaurant: Restaurant
    var exerciceID: UUID

    init(
        id: UUID = UUID(),
        fileName: String,
        fileType: FileType,
        status: ImportStatus = .pending,
        recordsCount: Int = 0,
        successCount: Int = 0,
        errorCount: Int = 0,
        timestamp: Date = Date(),
        errorDetails: String = "",
        restaurant: Restaurant = .freddy,
        exerciceID: UUID = UUID()
    ) {
        self.id = id
        self.fileName = fileName
        self.fileType = fileType
        self.status = status
        self.recordsCount = recordsCount
        self.successCount = successCount
        self.errorCount = errorCount
        self.timestamp = timestamp
        self.errorDetails = errorDetails
        self.restaurant = restaurant
        self.exerciceID = exerciceID
    }
}

enum FileType: String, Codable, CaseIterable {
    case invoicePDF = "Facture PDF"
    case balanceExcel = "Balance Excel"
    case bilanExcel = "Bilan Excel"
    case bankStatement = "Extrait bancaire"
    case payroll = "Paie"
    case vatDeclaration = "Déclaration TVA"
    case socialDeclaration = "Déclaration sociale"
    
    var icon: String {
        switch self {
        case .invoicePDF: return "doc.text"
        case .balanceExcel, .bilanExcel: return "tablecells"
        case .bankStatement: return "creditcard"
        case .payroll: return "eurosign"
        case .vatDeclaration, .socialDeclaration: return "doc.badge.gearshape"
        }
    }
}

enum ImportStatus: String, Codable, CaseIterable {
    case pending = "En cours"
    case success = "Réussi"
    case partialSuccess = "Partiel"
    case failed = "Échoué"
}
