import Foundation

public struct PackageSnapshot {
    public let id: PackageId
    public let externalKey: String
    public let numero: Int
    public let tipologia: String
    public let valore: Int
    public let unita: String
    public let volume: String
    public let denominazione: String?
    public let descrizioneFornitura: String?
    public let classeRimborsabilita: String?
    public let flagCommercio: Bool
    public let flagPrescrizione: Bool
    public let carente: Bool

    public init(
        id: PackageId,
        externalKey: String,
        numero: Int,
        tipologia: String,
        valore: Int,
        unita: String,
        volume: String,
        denominazione: String?,
        descrizioneFornitura: String?,
        classeRimborsabilita: String?,
        flagCommercio: Bool,
        flagPrescrizione: Bool,
        carente: Bool
    ) {
        self.id = id
        self.externalKey = externalKey
        self.numero = numero
        self.tipologia = tipologia
        self.valore = valore
        self.unita = unita
        self.volume = volume
        self.denominazione = denominazione
        self.descrizioneFornitura = descrizioneFornitura
        self.classeRimborsabilita = classeRimborsabilita
        self.flagCommercio = flagCommercio
        self.flagPrescrizione = flagPrescrizione
        self.carente = carente
    }
}
