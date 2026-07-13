//
//  ContentView.swift
//  LyricBar
//
//  Created by aiden on 7/12/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: LyricBarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            lyrics
            footer
        }
        .padding(24)
        .frame(minWidth: 620, idealWidth: 760, minHeight: 470)
        .background(.background)
        .onAppear {
            viewModel.start()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "music.note")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.trackTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text([viewModel.artistText, viewModel.albumText].filter { !$0.isEmpty }.joined(separator: " - "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if viewModel.isLoadingLyrics {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var lyrics: some View {
        VStack(spacing: 10) {
            lyricText(viewModel.previousLyric, size: 15, weight: .regular, color: .secondary)
                .frame(height: 34)

            if viewModel.statusText == LyricsState.plainLyrics.label {
                ScrollView {
                    lyricText(viewModel.currentLyric, size: 20, weight: .regular, color: .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 190)
            } else {
                lyricText(viewModel.currentLyric, size: 30, weight: .semibold, color: .primary)
                    .frame(maxWidth: .infinity, minHeight: 112)
            }

            lyricText(viewModel.nextLyric, size: 15, weight: .regular, color: .secondary)
                .frame(height: 34)
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressView(value: viewModel.progress)
                .progressViewStyle(.linear)

            HStack {
                Text(viewModel.playbackText)
                Text(viewModel.timeText)
                if !viewModel.sourceText.isEmpty {
                    Text(viewModel.sourceText)
                }
                Text(viewModel.statusText)
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !viewModel.detailText.isEmpty {
                Text(viewModel.detailText)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Label("싱크", systemImage: "timer")
                    .foregroundStyle(.secondary)

                Button {
                    viewModel.nudgeLyricSyncLater()
                } label: {
                    Image(systemName: "minus.circle")
                }
                .help("가사를 늦게 표시")

                Text(viewModel.lyricSyncOffsetText)
                    .font(.caption.monospacedDigit())
                    .frame(width: 52)

                Button {
                    viewModel.nudgeLyricSyncEarlier()
                } label: {
                    Image(systemName: "plus.circle")
                }
                .help("가사를 빠르게 표시")

                Button {
                    viewModel.resetLyricSyncOffset()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .help("싱크 보정 초기화")

                Spacer()
            }
            .font(.caption)
            .buttonStyle(.borderless)
            .disabled(!viewModel.canAdjustLyricSync)

            HStack(spacing: 10) {
                Button {
                    viewModel.importLRCFile()
                } label: {
                    Label("LRC 파일 불러오기", systemImage: "doc.badge.plus")
                }
                .disabled(!viewModel.canImportLRC)

                Button {
                    viewModel.deleteUserLyrics()
                } label: {
                    Label("사용자 가사 삭제", systemImage: "trash")
                }
                .disabled(!viewModel.canDeleteUserLyrics)

                Button {
                    viewModel.retrySearch()
                } label: {
                    Label("가사 다시 검색", systemImage: "arrow.clockwise")
                }
                .disabled(!viewModel.canImportLRC)

                Spacer()

                Toggle("디버그", isOn: $viewModel.showsDebugInfo)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                Toggle("Touch Bar 가사 표시", isOn: $viewModel.isTouchBarLyricsEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            HStack(spacing: 10) {
                Label("Touch Bar 폰트", systemImage: "textformat.size")
                    .foregroundStyle(.secondary)

                Picker("굵기", selection: $viewModel.touchBarFontWeight) {
                    ForEach(TouchBarLyricFontWeight.allCases) { weight in
                        Text(weight.label).tag(weight)
                    }
                }
                .labelsHidden()
                .frame(width: 118)

                Spacer()
            }
            .font(.caption)
            .disabled(!viewModel.isTouchBarLyricsEnabled)

            if viewModel.showsDebugInfo, !viewModel.selectedLRCLIBText.isEmpty {
                Text(viewModel.selectedLRCLIBText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }

            if viewModel.showsDebugInfo, !viewModel.appleMusicDebugText.isEmpty {
                Text(viewModel.appleMusicDebugText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(3)
            }

            if viewModel.showsDebugInfo, !viewModel.appleMusicAutomationDebugText.isEmpty {
                Text(viewModel.appleMusicAutomationDebugText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(3)
            }
        }
    }

    private func lyricText(_ text: String, size: CGFloat, weight: Font.Weight, color: Color) -> some View {
        Text(text.isEmpty ? " " : text)
            .font(.system(size: size, weight: weight, design: .rounded))
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .lineLimit(size > 24 ? 3 : 2)
            .minimumScaleFactor(0.55)
            .frame(maxWidth: .infinity)
    }
}
