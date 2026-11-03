struct ScanResult: Codable, Equatable, Sendable {
    let symbol: String
    let price: Double
    let priceCurrency: String?
    let anomalyScore: Double
    let priceAnomaly: Double?
    let volumeAnomaly: Double?
    let rangeAnomaly: Double?
    let relativeVolume: Double?
    let candleBodyRatio: Double
    let windowChangePercent: Double
    let windowVolume: Double
    let sessionVolume: Double
    let sessionTurnover: Double
    let signalAgeMinutes: Int
    let signalSource: String
    let updatedAtMillis: Int64
    let dataStatus: String
    let signalWindowLabel: String
    let signalPrice: Double
    let signalEpochMillis: Int64
    let bidPrice: Double?
    let askPrice: Double?
    let executableQuoteAtMillis: Int64
    let recentThreeMinutePercent: Double?
    let recentFiveMinutePercent: Double?
    let recentDirectionChanges: Int
    let repeatingCycleStrength: Double?
    let entryQualityScore: Int?
    let entryQualityConfidence: Int
    let entryQualityLabel: String
    let entryCooldownMinutes: Int
    let entryQualityDetails: String
    let analysisUpdatedAtMillis: Int64
    let scanEvaluatedAtMillis: Int64
    let isRetained: Bool

    init(
        symbol: String,
        price: Double,
        priceCurrency: String? = nil,
        anomalyScore: Double,
        priceAnomaly: Double?,
        volumeAnomaly: Double?,
        rangeAnomaly: Double?,
        relativeVolume: Double?,
        candleBodyRatio: Double,
        windowChangePercent: Double,
        windowVolume: Double,
        sessionVolume: Double,
        sessionTurnover: Double,
        signalAgeMinutes: Int,
        signalSource: String,
        updatedAtMillis: Int64,
        dataStatus: String = "CACHE",
        signalWindowLabel: String = "1m",
        signalPrice: Double? = nil,
        signalEpochMillis: Int64? = nil,
        bidPrice: Double? = nil,
        askPrice: Double? = nil,
        executableQuoteAtMillis: Int64 = 0,
        recentThreeMinutePercent: Double? = nil,
        recentFiveMinutePercent: Double? = nil,
        recentDirectionChanges: Int = 0,
        repeatingCycleStrength: Double? = nil,
        entryQualityScore: Int? = nil,
        entryQualityConfidence: Int = 0,
        entryQualityLabel: String = "Unavailable",
        entryCooldownMinutes: Int = 0,
        entryQualityDetails: String = "Entry-quality inputs are unavailable.",
        analysisUpdatedAtMillis: Int64? = nil,
        scanEvaluatedAtMillis: Int64? = nil,
        isRetained: Bool = false
    ) {
        self.symbol = symbol
        self.price = price
        self.priceCurrency = priceCurrency
        self.anomalyScore = anomalyScore
        self.priceAnomaly = priceAnomaly
        self.volumeAnomaly = volumeAnomaly
        self.rangeAnomaly = rangeAnomaly
        self.relativeVolume = relativeVolume
        self.candleBodyRatio = candleBodyRatio
        self.windowChangePercent = windowChangePercent
        self.windowVolume = windowVolume
        self.sessionVolume = sessionVolume
        self.sessionTurnover = sessionTurnover
        self.signalAgeMinutes = signalAgeMinutes
        self.signalSource = signalSource
        self.updatedAtMillis = updatedAtMillis
        self.dataStatus = dataStatus
        self.signalWindowLabel = signalWindowLabel
        self.signalPrice = signalPrice ?? price
        self.signalEpochMillis = signalEpochMillis ?? updatedAtMillis
        self.bidPrice = bidPrice
        self.askPrice = askPrice
        self.executableQuoteAtMillis = executableQuoteAtMillis
        self.recentThreeMinutePercent = recentThreeMinutePercent
        self.recentFiveMinutePercent = recentFiveMinutePercent
        self.recentDirectionChanges = recentDirectionChanges
        self.repeatingCycleStrength = repeatingCycleStrength
        self.entryQualityScore = entryQualityScore
        self.entryQualityConfidence = entryQualityConfidence
        self.entryQualityLabel = entryQualityLabel
        self.entryCooldownMinutes = entryCooldownMinutes
        self.entryQualityDetails = entryQualityDetails
        self.analysisUpdatedAtMillis = analysisUpdatedAtMillis ?? updatedAtMillis
        self.scanEvaluatedAtMillis = scanEvaluatedAtMillis ?? updatedAtMillis
        self.isRetained = isRetained
    }
}
