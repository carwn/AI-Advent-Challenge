//
//  MessageRow.swift
//  AI Advent Challenge
//
//  Created by Claude on 16.02.2026.
//

import SwiftUI

struct MessageRow: View {
    let message: Message

    var body: some View {
        if message.role == .summaryUsage {
            summaryUsageRow
        } else {
            regularRow
        }
    }

    // MARK: - Summary Usage Row

    private var isInternalMessage: Bool { message.content.hasPrefix("⚙️") }
    private var isPhaseMessage: Bool { message.content.hasPrefix("📍") }

    @ViewBuilder
    private var summaryUsageRow: some View {
        if isPhaseMessage {
            phaseRow
        } else {
            internalOrCompressionRow
        }
    }

    private var phaseRow: some View {
        HStack(spacing: 6) {
            tealLine
            Image(systemName: "arrow.forward.circle.fill")
                .font(.caption2)
                .foregroundStyle(.teal.opacity(0.8))
            Text(message.content)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.teal)
                .lineLimit(1)
            tealLine
        }
        .padding(.vertical, 4)
    }

    private var internalOrCompressionRow: some View {
        HStack(spacing: 6) {
            Image(systemName: isInternalMessage ? "gearshape" : "arrow.triangle.2.circlepath")
                .font(.caption2)
                .foregroundStyle(.purple.opacity(0.7))
                .fixedSize()
            summaryUsageContent
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.purple.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.purple.opacity(0.15), lineWidth: 0.5)
        )
        .padding(.horizontal, 8)
    }

    private var line: some View {
        VStack { Divider().overlay(Color.purple.opacity(0.3)) }
    }

    private var tealLine: some View {
        VStack { Divider().overlay(Color.teal.opacity(0.4)) }
    }

    private var summaryUsageContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            if isInternalMessage {
                Text(message.content)
                    .foregroundStyle(.purple.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                if let prompt = message.promptTokens, let completion = message.completionTokens {
                    HStack(spacing: 4) {
                        Text("↑\(prompt) ↓\(completion)")
                            .foregroundStyle(.secondary)
                        if let cost = summaryTotalCostRUB {
                            Text("·").foregroundStyle(.tertiary)
                            Text("₽\(fmtCost(cost))").foregroundStyle(.purple.opacity(0.8))
                        }
                    }
                }
            } else if let prompt = message.promptTokens, let completion = message.completionTokens {
                HStack(spacing: 4) {
                    Text("сжатие").foregroundStyle(.purple.opacity(0.8))
                    Text("↑\(prompt) ↓\(completion)").foregroundStyle(.secondary)
                    if let cost = summaryTotalCostRUB {
                        Text("·").foregroundStyle(.tertiary)
                        Text("₽\(fmtCost(cost))").foregroundStyle(.purple.opacity(0.8))
                    }
                }
            } else {
                Text("сжатие контекста").foregroundStyle(.purple.opacity(0.8))
            }
        }
        .font(.caption2.monospaced())
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryTotalCostRUB: Double? {
        guard let p = provider,
              let prompt = message.promptTokens,
              let completion = message.completionTokens else { return nil }
        let inputCost = Double(prompt) * p.pricingRUB.input / 1_000_000
        let outputCost = Double(completion) * p.pricingRUB.output / 1_000_000
        return inputCost + outputCost
    }

    // MARK: - Regular Row

    private var regularRow: some View {
        HStack {
            if message.role == .user {
                Spacer()
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(12)
                    .background(backgroundColor)
                    .foregroundColor(foregroundColor)
                    .cornerRadius(16)

                if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Вызовы инструментов:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(toolCalls) { toolCall in
                            Text("→ \(toolCall.function.name)")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    }
                    .padding(8)
                    .background(Color(uiColor: .systemGray6))
                    .cornerRadius(8)
                }

                HStack(spacing: 4) {
                    Text(message.timestamp, style: .time)
                    if let responseTime = message.responseTime {
                        Text("· \(formattedResponseTime(responseTime))")
                    }
                    if let modelName = message.modelName {
                        let display = ProviderType(rawValue: modelName)?.displayName ?? modelName
                        Text("· \(display)")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                if message.role == .assistant, message.promptTokens != nil || message.completionTokens != nil {
                    tokenCostRow
                }
            }

            if message.role == .assistant {
                Spacer()
            }
        }
    }

    private var provider: ProviderType? {
        guard let rawName = message.modelName else { return nil }
        return ProviderType(rawValue: rawName)
    }

    private var inputCostRUB: Double? {
        guard let tokens = message.promptTokens, let p = provider else { return nil }
        return Double(tokens) * p.pricingRUB.input / 1_000_000
    }

    private var outputCostRUB: Double? {
        guard let tokens = message.completionTokens, let p = provider else { return nil }
        let totalOutput = tokens + (message.thoughtsTokens ?? 0)
        return Double(totalOutput) * p.pricingRUB.output / 1_000_000
    }

    private func fmtCost(_ v: Double) -> String {
        v < 0.01 ? String(format: "%.4f", v) : String(format: "%.2f", v)
    }

    private var tokenCostRow: some View {
        HStack(spacing: 6) {
            HStack(spacing: 0) {
                Text("↑").foregroundStyle(.blue)
                Text("\(message.promptTokens ?? 0) ")
                Text("↓").foregroundStyle(.orange)
                Text("\(message.completionTokens ?? 0)")
                if let thoughts = message.thoughtsTokens {
                    Text(" (+\(thoughts))").foregroundStyle(.purple)
                }
            }
            if inputCostRUB != nil || outputCostRUB != nil {
                Text("·").foregroundStyle(.tertiary)
                HStack(spacing: 0) {
                    if let c = inputCostRUB {
                        Text("↑").foregroundStyle(.blue)
                        Text("₽\(fmtCost(c)) ")
                    }
                    if let c = outputCostRUB {
                        Text("↓").foregroundStyle(.orange)
                        Text("₽\(fmtCost(c)) ")
                    }
                    let total = (inputCostRUB ?? 0) + (outputCostRUB ?? 0)
                    Text("∑").foregroundStyle(.secondary)
                    Text("₽\(fmtCost(total))").foregroundStyle(.green)
                }
            }
        }
        .font(.caption2.monospaced())
        .foregroundStyle(.secondary)
    }

    private func formattedResponseTime(_ seconds: TimeInterval) -> String {
        if seconds < 10 {
            return String(format: "%.1f с", seconds)
        } else {
            return String(format: "%.0f с", seconds)
        }
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user:
            return .blue
        case .assistant:
            return Color(uiColor: .systemGray5)
        case .tool:
            return Color(uiColor: .systemGray6)
        case .system, .summaryUsage:
            return .clear
        }
    }

    private var foregroundColor: Color {
        message.role == .user ? .white : .primary
    }
}
