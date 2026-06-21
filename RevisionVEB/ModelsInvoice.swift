//
//  Invoice.swift
//  RevisionVEB
//
//  Created by eric bresler on 19/06/2026.
//

import Foundation
import SwiftData

@Model
final class Invoice {
    var id: UUID
    var number: String
    var date: Date
    var supplier: String
    var supplierCode: String
    var netAmount: Double
    var vatRate: Double
    var grossAmount: Double
    var paymentDate: Date?
    var status: InvoiceStatus
    var cycle: AuditCycle
    var sourceFile: String
    var restaurant: Restaurant
    var notes: String
    
    init(
        id: UUID = UUID(),
        number: String,
        date: Date,
        supplier: String,
        supplierCode: String = "",
        netAmount: Double,
        vatRate: Double,
        grossAmount: Double,
        paymentDate: Date? = nil,
        status: InvoiceStatus = .pending,
        cycle: AuditCycle = .fournisseurs,
        sourceFile: String = "",
        restaurant: Restaurant = .freddy,
        notes: String = ""
    ) {
        self.id = id
        self.number = number
        self.date = date
        self.supplier = supplier
        self.supplierCode = supplierCode
        self.netAmount = netAmount
        self.vatRate = vatRate
        self.grossAmount = grossAmount
        self.paymentDate = paymentDate
        self.status = status
        self.cycle = cycle
        self.sourceFile = sourceFile
        self.restaurant = restaurant
        self.notes = notes
    }
}

enum InvoiceStatus: String, Codable, CaseIterable {
    case pending = "En attente"
    case matched = "Rapproché"
    case paid = "Payé"
    case overdue = "En retard"
    case disputed = "Litige"
    case canceled = "Annulé"
}

enum AuditCycle: String, Codable, CaseIterable {
    case tresorerie = "B - Trésorerie"
    case fournisseurs = "E - Fournisseurs"
    case personnel = "H - Personnel"
    case fiscal = "I - Fiscal"
    
    var icon: String {
        switch self {
        case .tresorerie: return "banknote"
        case .fournisseurs: return "building.2"
        case .personnel: return "person.2"
        case .fiscal: return "doc.text"
        }
    }
}

enum Restaurant: String, Codable, CaseIterable {
    case freddy = "Freddy"
    case liesel = "Chez Tante Liesel"
}
