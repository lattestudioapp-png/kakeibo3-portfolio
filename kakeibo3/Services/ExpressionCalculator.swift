//
//  ExpressionCalculator.swift
//  kakeibo3
//
//  Created by 楠本陸 on 2026/06/03.
//


import Foundation

enum ExpressionCalculatorError: Error {
    case invalidExpression
    case divisionByZero
}

final class ExpressionCalculator {

    func calculate(_ expression: String) throws -> Int {
        let normalized = expression
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")

        guard !normalized.isEmpty else {
            throw ExpressionCalculatorError.invalidExpression
        }

        var parser = Parser(text: normalized)
        let value = try parser.parseExpression()

        guard parser.isAtEnd else {
            throw ExpressionCalculatorError.invalidExpression
        }

        guard value.isFinite else {
            throw ExpressionCalculatorError.invalidExpression
        }

        return Int(value.rounded())
    }
}

// MARK: - Parser

private struct Parser {
    private let characters: [Character]
    private var index: Int = 0

    init(text: String) {
        self.characters = Array(text)
    }

    var isAtEnd: Bool {
        index >= characters.count
    }

    mutating func parseExpression() throws -> Double {
        var value = try parseTerm()

        while !isAtEnd {
            let current = characters[index]

            if current == "+" {
                index += 1
                value += try parseTerm()
            } else if current == "-" {
                index += 1
                value -= try parseTerm()
            } else {
                break
            }
        }

        return value
    }

    private mutating func parseTerm() throws -> Double {
        var value = try parseFactor()

        while !isAtEnd {
            let current = characters[index]

            if current == "*" {
                index += 1
                value *= try parseFactor()
            } else if current == "/" {
                index += 1
                let divisor = try parseFactor()

                if divisor == 0 {
                    throw ExpressionCalculatorError.divisionByZero
                }

                value /= divisor
            } else {
                break
            }
        }

        return value
    }

    private mutating func parseFactor() throws -> Double {
        guard !isAtEnd else {
            throw ExpressionCalculatorError.invalidExpression
        }

        let current = characters[index]

        if current == "(" {
            index += 1
            let value = try parseExpression()

            guard !isAtEnd, characters[index] == ")" else {
                throw ExpressionCalculatorError.invalidExpression
            }

            index += 1
            return value
        }

        if current == "-" {
            index += 1
            let value = try parseFactor()
            return -value
        }

        return try parseNumber()
    }

    private mutating func parseNumber() throws -> Double {
        let startIndex = index

        while !isAtEnd {
            let current = characters[index]

            if current.isNumber || current == "." {
                index += 1
            } else {
                break
            }
        }

        guard startIndex != index else {
            throw ExpressionCalculatorError.invalidExpression
        }

        let numberString = String(characters[startIndex..<index])

        guard let value = Double(numberString) else {
            throw ExpressionCalculatorError.invalidExpression
        }

        return value
    }
}
