import SwiftUI
import AppKit
import UniformTypeIdentifiers
import LifeOSCore

/// 分享一次出行：先选带不带隐私信息，再选方式（微信文字 / 长图 / 日历文件；发布过的链接可以复制）
struct ShareTripSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let trip: Trip
    @State private var options = TripShare.Options()

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Text("分享「\(trip.title)」").font(.title2.bold())

            VStack(alignment: .leading, spacing: 6) {
                Text("这次带上：").font(.headline)
                Toggle("住址、确认号、订单号（发给家里人时可以打开）", isOn: $options.privateDetails)
                Toggle("价格和预算", isOn: $options.prices)
                Toggle("要带清单", isOn: $options.packing)
                Text("默认都不带。").font(.caption).foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: Theme.Space.m) {
                action("复制行程文字", "doc.on.doc", "粘贴到微信或 iMessage，按天列出安排") { copyText() }
                action("导出长图", "photo", "手机宽度的一张图，存到“下载”并复制到剪贴板，可以直接粘贴进微信") { exportImage() }
                action("导出到日历（.ics）", "calendar.badge.plus", "对方打开文件，安排和期限就进了他们的日历") { exportICS() }
                if let url = trip.shareURL {
                    HStack {
                        Text(url.absoluteString).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Button("复制链接") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(url.absoluteString, forType: .string)
                            model.feedback.show("链接已复制")
                        }
                        .controlSize(.small)
                    }
                }
            }

            HStack {
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 480)
    }

    private func action(_ title: String, _ icon: String, _ detail: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon).frame(width: 22).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).fontWeight(.medium)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(TripShare.text(trip, options: options, calendar: model.calendar), forType: .string)
        model.feedback.show("行程文字已复制，去微信粘贴")
    }

    private var downloads: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    private func safeName(_ ext: String) -> String {
        trip.title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-") + "." + ext
    }

    @MainActor
    private func exportImage() {
        let renderer = ImageRenderer(content: ShareImageCard(trip: trip, options: options, calendar: model.calendar))
        renderer.scale = 3
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            model.feedback.show("没能生成长图")
            return
        }
        let url = downloads.appendingPathComponent(safeName("png"))
        do {
            try png.write(to: url)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
            model.reveal(url)
            model.feedback.show("长图已存到“下载”，也复制好了，可以直接粘贴进微信")
        } catch {
            model.feedback.show("没能保存长图：\(error.localizedDescription)")
        }
    }

    private func exportICS() {
        let url = downloads.appendingPathComponent(safeName("ics"))
        do {
            try TripShare.ics(trip, options: options, calendar: model.calendar).write(to: url, atomically: true, encoding: .utf8)
            model.reveal(url)
            model.feedback.show("日历文件已存到“下载”，发给同学，对方打开就能加进日历")
        } catch {
            model.feedback.show("没能保存日历文件：\(error.localizedDescription)")
        }
    }
}

/// 长图：手机宽度，只用传进来的数据（ImageRenderer 里拿不到 App 的环境）
struct ShareImageCard: View {
    let trip: Trip
    let options: TripShare.Options
    let calendar: Calendar

    var body: some View {
        let route = trip.route.isEmpty ? trip.destination : trip.route
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(trip.title).font(.system(size: 26, weight: .bold))
                if !route.isEmpty { Text(route).font(.system(size: 16)).foregroundStyle(.secondary) }
                Text(TripShare.dateRange(trip, calendar: calendar)
                     + (trip.with.isEmpty ? "" : " · 同行：\(trip.with)")
                     + (trip.transport.isEmpty ? "" : " · \(trip.transport)"))
                    .font(.system(size: 14)).foregroundStyle(.secondary)
            }
            ForEach(trip.days) { day in
                VStack(alignment: .leading, spacing: 8) {
                    Text("第 \(day.index) 天" + (day.date.map { " · \(TripShare.md($0, calendar)) \(TripShare.weekday($0, calendar))" } ?? "")
                         + (day.city.isEmpty ? "" : " · \(day.city)"))
                        .font(.system(size: 17, weight: .semibold))
                    if day.items.isEmpty {
                        Text("还没排").font(.system(size: 14)).foregroundStyle(.secondary)
                    }
                    ForEach(day.items) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Text(item.time.isEmpty ? "—" : item.time)
                                .font(.system(size: 13).monospacedDigit()).foregroundStyle(Color(red: 0.11, green: 0.31, blue: 0.85))
                                .frame(width: 86, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.text).font(.system(size: 15, weight: .medium))
                                if !item.place.isEmpty { Text(item.place).font(.system(size: 13)).foregroundStyle(.secondary) }
                            }
                        }
                    }
                    if let l = TripShare.lodgingFor(day, trip, calendar) {
                        Text("🛏 今晚住：\(l.name)" + (options.privateDetails && !l.address.isEmpty ? "（\(l.address)）" : ""))
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            }
            let notes = TripShare.plainLines(trip.section("地点")) + TripShare.plainLines(trip.section("证件"))
            if !notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("须知").font(.system(size: 17, weight: .semibold))
                    ForEach(Array(notes.enumerated()), id: \.offset) { _, n in
                        Text("•  " + n.dropFirst(2)).font(.system(size: 13))
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            }
            if options.packing && !trip.packing.isEmpty {
                Text("要带：" + trip.packing.map(\.text).joined(separator: "、")).font(.system(size: 13))
            }
            Text("LifeOS").font(.system(size: 11)).foregroundStyle(.tertiary).frame(maxWidth: .infinity)
        }
        .foregroundStyle(Color(white: 0.12))
        .padding(20)
        .frame(width: 400, alignment: .leading)
        .background(Color(red: 0.97, green: 0.96, blue: 0.94))
        .environment(\.colorScheme, .light)
    }
}
