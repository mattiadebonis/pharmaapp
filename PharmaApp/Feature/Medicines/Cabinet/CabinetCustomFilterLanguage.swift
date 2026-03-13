import Foundation

enum CabinetCustomFilterField: Hashable {
    case name
    case label
    case stock
    case therapy
    case rx
    case cabinet
    case deadline
}

enum CabinetCustomFilterStockValue: String, Hashable {
    case ok
    case low
    case out
}

enum CabinetCustomFilterDeadlineValue: String, Hashable {
    case none
    case ok
    case soon
    case expired
}

enum CabinetCustomFilterValue: Hashable {
    case text(String)
    case bool(Bool)
    case stock(CabinetCustomFilterStockValue)
    case deadline(CabinetCustomFilterDeadlineValue)
}

struct CabinetCustomFilterTerm: Hashable {
    let field: CabinetCustomFilterField
    let value: CabinetCustomFilterValue
}

indirect enum CabinetCustomFilterExpression: Hashable {
    case term(CabinetCustomFilterTerm)
    case and(CabinetCustomFilterExpression, CabinetCustomFilterExpression)
    case or(CabinetCustomFilterExpression, CabinetCustomFilterExpression)
    case not(CabinetCustomFilterExpression)
}

struct CabinetCustomFilterContext: Hashable {
    let name: String
    let labels: [String]
    let stock: CabinetCustomFilterStockValue
    let hasTherapy: Bool
    let requiresPrescription: Bool
    let cabinetNames: [String]
    let deadline: CabinetCustomFilterDeadlineValue
}

struct CabinetCustomFilterLanguageError: LocalizedError, Equatable {
    let message: String
    let position: Int

    var errorDescription: String? {
        "\(message) (posizione \(position + 1))"
    }
}

struct CabinetCustomFilterQueryParser {
    func parse(_ raw: String) throws -> CabinetCustomFilterExpression {
        var tokenizer = Tokenizer(input: raw)
        let tokens = try tokenizer.tokenize()
        var parser = Parser(tokens: tokens)
        return try parser.parse()
    }

    private enum Symbol: Equatable {
        case colon
        case lParen
        case rParen
        case and
        case or
        case not
    }

    private enum TokenKind: Equatable {
        case word(String)
        case string(String)
        case symbol(Symbol)
        case end
    }

    private struct Token: Equatable {
        let kind: TokenKind
        let position: Int
    }

    private struct Tokenizer {
        let input: String

        mutating func tokenize() throws -> [Token] {
            let chars = Array(input)
            var index = 0
            var tokens: [Token] = []

            while index < chars.count {
                let ch = chars[index]
                if ch.isWhitespace {
                    index += 1
                    continue
                }

                let position = index
                if ch == ":" {
                    tokens.append(Token(kind: .symbol(.colon), position: position))
                    index += 1
                    continue
                }
                if ch == "(" {
                    tokens.append(Token(kind: .symbol(.lParen), position: position))
                    index += 1
                    continue
                }
                if ch == ")" {
                    tokens.append(Token(kind: .symbol(.rParen), position: position))
                    index += 1
                    continue
                }
                if ch == "\"" {
                    let stringToken = try readString(chars: chars, index: &index, position: position)
                    tokens.append(stringToken)
                    continue
                }

                let start = index
                while index < chars.count {
                    let current = chars[index]
                    if current.isWhitespace || current == ":" || current == "(" || current == ")" {
                        break
                    }
                    index += 1
                }

                let rawWord = String(chars[start..<index])
                let keyword = rawWord.uppercased()
                switch keyword {
                case "AND":
                    tokens.append(Token(kind: .symbol(.and), position: start))
                case "OR":
                    tokens.append(Token(kind: .symbol(.or), position: start))
                case "NOT":
                    tokens.append(Token(kind: .symbol(.not), position: start))
                default:
                    tokens.append(Token(kind: .word(rawWord), position: start))
                }
            }

            tokens.append(Token(kind: .end, position: chars.count))
            return tokens
        }

        private func readString(chars: [Character], index: inout Int, position: Int) throws -> Token {
            index += 1 // Skip opening quote
            var value = ""
            var isClosed = false

            while index < chars.count {
                let ch = chars[index]
                if ch == "\\" {
                    let nextIndex = index + 1
                    guard nextIndex < chars.count else {
                        throw CabinetCustomFilterLanguageError(
                            message: "Escape non valido nella stringa.",
                            position: index
                        )
                    }
                    value.append(chars[nextIndex])
                    index = nextIndex + 1
                    continue
                }
                if ch == "\"" {
                    isClosed = true
                    index += 1
                    break
                }

                value.append(ch)
                index += 1
            }

            guard isClosed else {
                throw CabinetCustomFilterLanguageError(
                    message: "Stringa non chiusa.",
                    position: position
                )
            }

            return Token(kind: .string(value), position: position)
        }
    }

    private struct Parser {
        private let tokens: [Token]
        private var index: Int = 0

        init(tokens: [Token]) {
            self.tokens = tokens
        }

        mutating func parse() throws -> CabinetCustomFilterExpression {
            if case .end = current.kind {
                throw CabinetCustomFilterLanguageError(message: "Query vuota.", position: current.position)
            }

            let expression = try parseOr()
            if case .end = current.kind {
                return expression
            }

            throw CabinetCustomFilterLanguageError(
                message: "Token non previsto alla fine della query.",
                position: current.position
            )
        }

        private mutating func parseOr() throws -> CabinetCustomFilterExpression {
            var expression = try parseAnd()
            while match(symbol: .or) {
                let rhs = try parseAnd()
                expression = .or(expression, rhs)
            }
            return expression
        }

        private mutating func parseAnd() throws -> CabinetCustomFilterExpression {
            var expression = try parseUnary()
            while true {
                if match(symbol: .and) {
                    let rhs = try parseUnary()
                    expression = .and(expression, rhs)
                    continue
                }

                if canStartUnary(current.kind) {
                    let rhs = try parseUnary()
                    expression = .and(expression, rhs)
                    continue
                }

                break
            }
            return expression
        }

        private mutating func parseUnary() throws -> CabinetCustomFilterExpression {
            if match(symbol: .not) {
                return .not(try parseUnary())
            }
            return try parsePrimary()
        }

        private mutating func parsePrimary() throws -> CabinetCustomFilterExpression {
            if match(symbol: .lParen) {
                let expression = try parseOr()
                guard match(symbol: .rParen) else {
                    throw CabinetCustomFilterLanguageError(
                        message: "Parentesi chiusa mancante.",
                        position: current.position
                    )
                }
                return expression
            }

            return .term(try parseTerm())
        }

        private mutating func parseTerm() throws -> CabinetCustomFilterTerm {
            guard case let .word(rawField) = current.kind else {
                throw CabinetCustomFilterLanguageError(
                    message: "Atteso il nome di un campo.",
                    position: current.position
                )
            }
            let fieldPosition = current.position
            advance()

            guard match(symbol: .colon) else {
                throw CabinetCustomFilterLanguageError(
                    message: "Atteso ':' dopo il campo.",
                    position: current.position
                )
            }

            let valueToken = current
            let rawValue: String
            switch valueToken.kind {
            case let .word(value), let .string(value):
                rawValue = value
            default:
                throw CabinetCustomFilterLanguageError(
                    message: "Atteso il valore del campo.",
                    position: valueToken.position
                )
            }
            advance()

            let field = try parseField(rawField, position: fieldPosition)
            let parsedValue = try parseValue(rawValue, for: field, position: valueToken.position)
            return CabinetCustomFilterTerm(field: field, value: parsedValue)
        }

        private mutating func match(symbol: Symbol) -> Bool {
            guard case let .symbol(currentSymbol) = current.kind,
                  currentSymbol == symbol else {
                return false
            }
            advance()
            return true
        }

        private mutating func advance() {
            if index < tokens.count - 1 {
                index += 1
            }
        }

        private func canStartUnary(_ kind: TokenKind) -> Bool {
            switch kind {
            case .word:
                return true
            case .symbol(.lParen), .symbol(.not):
                return true
            default:
                return false
            }
        }

        private func parseField(_ rawField: String, position: Int) throws -> CabinetCustomFilterField {
            switch normalizeToken(rawField) {
            case "name", "nome":
                return .name
            case "label", "etichetta":
                return .label
            case "stock", "scorte":
                return .stock
            case "therapy", "terapia":
                return .therapy
            case "rx", "ricetta":
                return .rx
            case "cabinet", "armadietto":
                return .cabinet
            case "deadline", "scadenza":
                return .deadline
            default:
                throw CabinetCustomFilterLanguageError(
                    message: "Campo '\(rawField)' non supportato.",
                    position: position
                )
            }
        }

        private func parseValue(
            _ rawValue: String,
            for field: CabinetCustomFilterField,
            position: Int
        ) throws -> CabinetCustomFilterValue {
            let normalizedValue = normalizeToken(rawValue)
            switch field {
            case .name, .label, .cabinet:
                let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    throw CabinetCustomFilterLanguageError(
                        message: "Valore vuoto non valido.",
                        position: position
                    )
                }
                return .text(trimmed)
            case .therapy, .rx:
                guard let boolValue = boolValue(from: normalizedValue) else {
                    throw CabinetCustomFilterLanguageError(
                        message: "Valore booleano non valido per '\(fieldLabel(field))'.",
                        position: position
                    )
                }
                return .bool(boolValue)
            case .stock:
                guard let stockValue = stockValue(from: normalizedValue) else {
                    throw CabinetCustomFilterLanguageError(
                        message: "Valore scorte non valido.",
                        position: position
                    )
                }
                return .stock(stockValue)
            case .deadline:
                guard let deadlineValue = deadlineValue(from: normalizedValue) else {
                    throw CabinetCustomFilterLanguageError(
                        message: "Valore scadenza non valido.",
                        position: position
                    )
                }
                return .deadline(deadlineValue)
            }
        }

        private func normalizeToken(_ raw: String) -> String {
            raw
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .lowercased()
                .replacingOccurrences(of: "-", with: "_")
                .replacingOccurrences(of: " ", with: "_")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private func boolValue(from normalized: String) -> Bool? {
            switch normalized {
            case "true", "yes", "si", "s", "1":
                return true
            case "false", "no", "n", "0":
                return false
            default:
                return nil
            }
        }

        private func stockValue(from normalized: String) -> CabinetCustomFilterStockValue? {
            switch normalized {
            case "ok", "a_posto", "aposto":
                return .ok
            case "low", "in_esaurimento", "esaurimento", "basse", "bassa":
                return .low
            case "out", "finite", "esaurite", "esaurita", "critical", "critico", "critica":
                return .out
            default:
                return nil
            }
        }

        private func deadlineValue(from normalized: String) -> CabinetCustomFilterDeadlineValue? {
            switch normalized {
            case "none", "nessuna", "no":
                return CabinetCustomFilterDeadlineValue.none
            case "ok":
                return .ok
            case "soon", "vicina":
                return .soon
            case "expired", "scaduta", "scaduto":
                return .expired
            default:
                return nil
            }
        }

        private func fieldLabel(_ field: CabinetCustomFilterField) -> String {
            switch field {
            case .name:
                return "name"
            case .label:
                return "label"
            case .stock:
                return "stock"
            case .therapy:
                return "therapy"
            case .rx:
                return "rx"
            case .cabinet:
                return "cabinet"
            case .deadline:
                return "deadline"
            }
        }

        private var current: Token {
            tokens[index]
        }
    }
}

struct CabinetCustomFilterEvaluator {
    func matches(_ expression: CabinetCustomFilterExpression, in context: CabinetCustomFilterContext) -> Bool {
        switch expression {
        case .term(let term):
            return matches(term, in: context)
        case let .and(lhs, rhs):
            return matches(lhs, in: context) && matches(rhs, in: context)
        case let .or(lhs, rhs):
            return matches(lhs, in: context) || matches(rhs, in: context)
        case .not(let expr):
            return !matches(expr, in: context)
        }
    }

    private func matches(_ term: CabinetCustomFilterTerm, in context: CabinetCustomFilterContext) -> Bool {
        switch (term.field, term.value) {
        case let (.name, .text(text)):
            return normalized(context.name).contains(normalized(text))
        case let (.label, .text(text)):
            let value = normalized(text)
            return context.labels.contains { normalized($0) == value }
        case let (.cabinet, .text(text)):
            let value = normalized(text)
            return context.cabinetNames.contains { normalized($0).contains(value) }
        case let (.therapy, .bool(boolValue)):
            return context.hasTherapy == boolValue
        case let (.rx, .bool(boolValue)):
            return context.requiresPrescription == boolValue
        case let (.stock, .stock(stockValue)):
            return context.stock == stockValue
        case let (.deadline, .deadline(deadlineValue)):
            return context.deadline == deadlineValue
        default:
            return false
        }
    }

    private func normalized(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
