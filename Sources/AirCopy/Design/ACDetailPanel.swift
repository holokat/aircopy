import AppKit
import SwiftUI

struct ACSendTarget: Identifiable {
    let id: String
    let name: String
    let symbol: String
    let enabled: Bool
}

struct ACDetailPanel: View {
    let item: ClipboardHistoryItem
    let thumbnail: NSImage?
    let sendTargets: [ACSendTarget]
    let onClose: () -> Void
    let onCopy: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void
    let onSend: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    previewTile
                    metadataList
                    actions
                    sendSection
                }
                .padding(18)
            }
        }
        .frame(width: 346)
        .background(ACColor.sidebar)
        .overlay(alignment: .leading) { Rectangle().fill(ACColor.border08).frame(width: 1) }
    }

    private var header: some View {
        HStack {
            Text("Details")
                .font(ACFont.sans(14, weight: .semibold))
                .foregroundStyle(ACColor.ink)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ACColor.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(ACColor.controlHover, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 18)
        .padding(.trailing, 16)
        .frame(height: 58)
        .overlay(alignment: .bottom) { Rectangle().fill(ACColor.border08).frame(height: 1) }
    }

    @ViewBuilder
    private var previewTile: some View {
        VStack(spacing: 0) {
            switch item.cardKind {
            case .text:
                ScrollView {
                    Text(item.textPreview)
                        .font(item.isMonospaced ? ACFont.mono(13.5) : ACFont.sans(13.5))
                        .foregroundStyle(ACColor.ink2)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .textSelection(.enabled)
                        .padding(17)
                }
                .frame(maxHeight: 210)
            case .image:
                Group {
                    if let thumbnail {
                        Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        LinearGradient(colors: [Color(hex: 0x2A3380), Color(hex: 0x6A3FB0)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                }
                .frame(height: 188)
                .frame(maxWidth: .infinity)
                .clipped()
            case .link:
                VStack(alignment: .leading, spacing: 12) {
                    Text(item.faviconLetter)
                        .font(ACFont.sans(17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(ACColor.favicon(for: item.linkDomain), in: RoundedRectangle(cornerRadius: 10))
                    Text(item.linkTitleText)
                        .font(ACFont.sans(15, weight: .semibold))
                        .foregroundStyle(ACColor.ink2)
                    Text(item.linkURLText)
                        .font(ACFont.mono(11.5))
                        .foregroundStyle(ACColor.accent)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
            case .color:
                let hex = item.colorHex ?? "#000000"
                ZStack(alignment: .bottomLeading) {
                    (Color(hexString: hex) ?? .black)
                    Text(hex)
                        .font(ACFont.mono(16, weight: .medium))
                        .foregroundStyle(Color.readableInk(onHex: hex))
                        .padding(14)
                }
                .frame(height: 150)
            }
        }
        .frame(maxWidth: .infinity)
        .background(ACColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .acBorder(ACColor.border09, radius: 14)
    }

    private var metadataList: some View {
        VStack(spacing: 1) {
            metaRow("Type", item.typeLabel)
            metaRow("From", item.senderName)
            metaRow("Captured", item.relativeAgo)
            metaRow(item.extraMetadata.label, item.extraMetadata.value)
        }
        .background(ACColor.border08)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .acBorder(ACColor.border08, radius: 12)
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(ACFont.sans(12.5))
                .foregroundStyle(ACColor.textTertiary)
            Spacer()
            Text(value)
                .font(ACFont.sans(12.5, weight: .medium))
                .foregroundStyle(ACColor.ink)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(ACColor.surface)
    }

    private var actions: some View {
        VStack(spacing: 9) {
            Button(action: onCopy) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.on.doc").font(.system(size: 14))
                    Text("Copy to clipboard").font(ACFont.sans(14, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(ACColor.accent, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)

            HStack(spacing: 9) {
                Button(action: onPin) {
                    HStack(spacing: 7) {
                        Image(systemName: item.isPinned ? "pin.fill" : "pin").font(.system(size: 12))
                        Text(item.isPinned ? "Unpin" : "Pin").font(ACFont.sans(13, weight: .medium))
                    }
                    .foregroundStyle(item.isPinned ? ACColor.accent : ACColor.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(ACColor.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .acBorder(ACColor.border10, radius: 11)
                }
                .buttonStyle(.plain)

                Button(action: onDelete) {
                    HStack(spacing: 7) {
                        Image(systemName: "trash").font(.system(size: 12))
                        Text("Delete").font(ACFont.sans(13, weight: .medium))
                    }
                    .foregroundStyle(ACColor.danger)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(ACColor.dangerSoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .acBorder(ACColor.dangerBorder, radius: 11)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var sendSection: some View {
        if !sendTargets.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("SEND TO DEVICE")
                    .font(ACFont.sans(10.5, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(ACColor.textTertiary)
                    .padding(.top, 12)
                    .padding(.horizontal, 2)
                ForEach(sendTargets) { target in
                    Button {
                        if target.enabled { onSend(target.id) }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: target.symbol)
                                .font(.system(size: 13))
                                .foregroundStyle(target.enabled ? ACColor.textSecondary : ACColor.textTertiary2)
                            Text(target.name)
                                .font(ACFont.sans(13, weight: .medium))
                                .foregroundStyle(target.enabled ? ACColor.ink : ACColor.textTertiary)
                            Spacer()
                            if !target.enabled {
                                Text("paused")
                                    .font(ACFont.sans(11))
                                    .foregroundStyle(ACColor.textTertiary2)
                            }
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 11)
                        .background(ACColor.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .acBorder(ACColor.border09, radius: 11)
                    }
                    .buttonStyle(.plain)
                    .disabled(!target.enabled)
                }
            }
        }
    }
}
