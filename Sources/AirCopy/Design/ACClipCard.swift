import AppKit
import SwiftUI

struct ACClipCard: View {
    let item: ClipboardHistoryItem
    let deviceName: String
    let isSelected: Bool
    let isCopied: Bool
    let thumbnail: NSImage?
    let onOpen: () -> Void
    let onCopy: () -> Void
    let onPin: () -> Void

    @State private var hovering = false

    private var pinned: Bool { item.isPinned }

    var body: some View {
        Button(action: onOpen) {
            VStack(spacing: 0) {
                body(for: item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()

                footer
            }
            .frame(height: 172)
            .background(ACColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .acBorder(isSelected ? ACColor.accent : ACColor.border09, radius: 15, width: isSelected ? 2 : 1)
            .overlay(alignment: .topTrailing) { pinButton }
            .offset(y: hovering ? -3 : 0)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: hovering)
        .onHover { hovering = $0 }
    }

    // MARK: - Bodies

    @ViewBuilder
    private func body(for item: ClipboardHistoryItem) -> some View {
        switch item.cardKind {
        case .text: textBody
        case .image: imageBody
        case .link: linkBody
        case .color: colorBody
        }
    }

    private var textBody: some View {
        Text(item.textPreview)
            .font(item.isMonospaced ? ACFont.mono(13) : ACFont.sans(13))
            .foregroundStyle(ACColor.ink2)
            .lineSpacing(3)
            .lineLimit(4)
            .truncationMode(.tail)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 15)
            .padding(.top, 15)
            .padding(.bottom, 12)
    }

    private var imageBody: some View {
        ZStack(alignment: .bottomLeading) {
            // Color.clear takes exactly the available cell space; the image is an
            // overlay so its (possibly huge) size can't expand the card's layout.
            Color.clear
                .overlay {
                    if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                    } else {
                        LinearGradient(
                            colors: [Color(hex: 0x2A3380), Color(hex: 0x6A3FB0)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    }
                }
                .clipped()

            // filename bar
            HStack(spacing: 6) {
                Text("PNG")
                    .font(ACFont.sans(9, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 5))
                Text(item.imageFilename)
                    .font(ACFont.sans(11))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [.clear, .black.opacity(0.32)], startPoint: .top, endPoint: .bottom)
            )
        }
    }

    private var linkBody: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                Text(item.faviconLetter)
                    .font(ACFont.sans(12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(ACColor.favicon(for: item.linkDomain), in: RoundedRectangle(cornerRadius: 7))
                Text(item.linkDomain)
                    .font(ACFont.sans(12, weight: .medium))
                    .foregroundStyle(ACColor.textSecondary2)
            }
            Text(item.linkTitleText)
                .font(ACFont.sans(13.5, weight: .medium))
                .foregroundStyle(ACColor.ink2)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(item.linkURLText)
                .font(ACFont.mono(11))
                .foregroundStyle(ACColor.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(15)
    }

    private var colorBody: some View {
        let hex = item.colorHex ?? "#000000"
        return HStack(spacing: 15) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(hexString: hex) ?? .black)
                .frame(width: 58, height: 58)
                .acBorder(ACColor.border10, radius: 14)
            VStack(alignment: .leading, spacing: 3) {
                Text(hex)
                    .font(ACFont.mono(15, weight: .medium))
                    .foregroundStyle(ACColor.ink2)
                Text("Solid color")
                    .font(ACFont.sans(12))
                    .foregroundStyle(ACColor.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(18)
    }

    // MARK: - Footer & pin

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: deviceSymbol)
                .font(.system(size: 12))
                .foregroundStyle(ACColor.textTertiary)
            Text("\(deviceName) · \(item.relativeAgo)")
                .font(ACFont.sans(11.5))
                .foregroundStyle(ACColor.textSecondary2)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            Button(action: onCopy) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 13, weight: isCopied ? .bold : .regular))
                    .foregroundStyle(isCopied ? ACColor.successText : ACColor.accent)
                    .frame(width: 27, height: 27)
                    .background(isCopied ? ACColor.success.opacity(0.14) : ACColor.accentSoft, in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .opacity(hovering || isCopied ? 1 : 0)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(ACColor.inset)
        .overlay(alignment: .top) { Rectangle().fill(ACColor.border06).frame(height: 1) }
    }

    private var pinButton: some View {
        Button(action: onPin) {
            Image(systemName: pinned ? "pin.fill" : "pin")
                .font(.system(size: 12))
                .foregroundStyle(pinned ? ACColor.accent : ACColor.textTertiary2)
                .frame(width: 27, height: 27)
                .background(pinned ? ACColor.accentSoft16 : ACColor.controlSearch, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .padding(9)
        .opacity(hovering || pinned ? 1 : 0)
    }

    private var deviceSymbol: String { deviceSFSymbolName(for: deviceName) }
}
