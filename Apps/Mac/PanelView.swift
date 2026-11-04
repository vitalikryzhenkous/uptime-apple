import SwiftUI
import UptimeKit

/// The menu-bar panel, design "A on Mac": Buddy, plan limits, sessions (who needs you first), machine and weather.
struct PanelView: View {
    @Environment(LiveStore.self) private var store
    @Environment(AssetStore.self) private var assets
    @Environment(\.colorScheme) private var scheme
    @State private var expanded: Set<String> = []

    var body: some View {
        let t = Theme.of(scheme)
        let s = assets.strings
        // durations tick between status events
        TimelineView(.periodic(from: .now, by: 15)) { ctx in
            let now = store.serverNow(ctx.date)
            VStack(alignment: .leading, spacing: 10) {
                header(t, s)
                if store.connection != .live {
                    ConnectionLine(connection: store.connection, lastUpdate: store.lastUpdate, strings: s, theme: t)
                }
                if let st = store.status {
                    if let lim = st.claude?.limits, lim.h5 != nil || lim.d7 != nil {
                        LimitsCard(limits: lim, now: now, t: t, s: s)
                    }
                    sessions(st, now: now, t, s)
                }
                buttons(t, s)
                footer(t, s)
            }
        }
        .padding(14)
        .frame(width: 400, alignment: .leading)
        .foregroundStyle(t.fg)
        .panelBackground(t)
    }

    // MARK: parts

    @ViewBuilder
    private func header(_ t: Theme, _ s: Strings) -> some View {
        let st = store.status
        HStack(alignment: .top, spacing: 10) {
            if let sprites = assets.sprites, let look = st?.cat?.look {
                BuddyView(sprites: sprites, look: look, pixel: 3,
                          busy: st?.streams.contains { $0.stateKind == .working } ?? false)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text((assets.ext?.persona?.name ?? st?.persona?.name ?? "Buddy").uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(t.b)
                if let cat = st?.cat {
                    Text(s.text(for: cat))
                        .font(.system(size: 13))
                        .foregroundStyle(t.g2)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power").foregroundStyle(t.g2)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
            .help(s.tr("app.quit", fallback: "Quit"))
            .accessibilityLabel(s.tr("app.quit", fallback: "Quit"))
        }
    }

    @ViewBuilder
    private func sessions(_ st: Status, now: Double, _ t: Theme, _ s: Strings) -> some View {
        let rows = Panel.sorted(st.streams)
        if rows.isEmpty {
            Text(s.tr("app.no_agents", fallback: "No agents running — time to breathe."))
                .font(.callout)
                .foregroundStyle(t.g2)
                .padding(.vertical, 6)
        } else {
            let list = VStack(spacing: 6) {
                ForEach(rows) { r in
                    SessionRow(stream: r, git: r.folder.flatMap { st.git?[$0] }, now: now,
                               expanded: expanded.contains(r.id), t: t, s: s) {
                        if expanded.contains(r.id) { expanded.remove(r.id) } else { expanded.insert(r.id) }
                    }
                }
            }
            // a scroll view would always take its full height; only use one when the list is long
            if rows.count > 5 || !expanded.isEmpty {
                ScrollView { list }.frame(height: 360)
            } else {
                list
            }
        }
    }

    @ViewBuilder
    private func buttons(_ t: Theme, _ s: Strings) -> some View {
        HStack(spacing: 8) {
            SettingsLink {
                Text(s.tr("app.settings", fallback: "Settings…"))
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.plain)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(t.line))
            .simultaneousGesture(TapGesture().onEnded { NSApp.activate() })

            if store.connection != .live {
                Button { store.start() } label: {
                    Text(s.tr("app.reconnect", fallback: "Reconnect"))
                        .fontWeight(.semibold)
                        .foregroundStyle(t.on)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(t.b, in: .rect(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func footer(_ t: Theme, _ s: Strings) -> some View {
        let st = store.status
        HStack {
            if let m = st?.machine {
                Text("M920Q · CPU \(Int(m.cpu ?? 0))% · RAM \(Int(m.ram ?? 0))%")
            }
            if store.connection == .live, let u = store.lastUpdate {
                Text("· " + s.tr("app.conn.live", ["time": .string(u.formatted(date: .omitted, time: .shortened))],
                                 fallback: "updated \(u.formatted(date: .omitted, time: .shortened))"))
            }
            Spacer()
            if let w = st?.weather, let temp = w.temp {
                let sign = temp > 0 ? "+" : ""
                let word = w.key.map { s.tr($0, fallback: w.text ?? "") } ?? (w.text ?? "")
                Text("\(sign)\(Int(temp))° \(word.lowercased().capitalizedFirst)")
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(t.g2)
        .lineLimit(1)
    }
}

// MARK: - Limits

struct LimitsCard: View {
    let limits: Limits
    let now: Double
    let t: Theme
    let s: Strings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let h5 = limits.h5 {
                bar(s.tr("app.limit.h5", fallback: "5 h"), pct: h5.pct, level: Panel.h5Level(h5.pct))
            }
            if let d7 = limits.d7, Panel.weekIsBig(d7.pct) {
                bar(s.tr("app.limit.week", fallback: "week"), pct: d7.pct, level: Panel.weekLevel(d7.pct))
            }
            let sub = subline
            if !sub.isEmpty {
                Text(sub).font(.system(size: 12)).foregroundStyle(t.g2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(t.card, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private var subline: String {
        var parts: [String] = []
        if let reset = limits.h5?.reset, reset > now {
            let left = Panel.duration(reset - now, s)
            parts.append(s.tr("app.limit.reset_in", ["t": .string(left)], fallback: "resets in \(left)"))
        }
        if let d7 = limits.d7, !Panel.weekIsBig(d7.pct) {
            parts.append("\(s.tr("app.limit.week", fallback: "week")) \(Int(d7.pct.rounded()))%")
        }
        return parts.joined(separator: " · ")
    }

    private func bar(_ label: String, pct: Double, level: Level) -> some View {
        HStack(spacing: 8) {
            Text(label).fontWeight(.semibold).frame(width: 52, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(t.line)
                    Capsule().fill(t.color(level)).frame(width: g.size.width * min(1, max(0, pct / 100)))
                }
            }
            .frame(height: 8)
            Text("\(Int(pct.rounded()))%")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(level == .ok ? t.fg : t.color(level))
                .frame(width: 44, alignment: .trailing)
        }
    }
}

// MARK: - One session

struct SessionRow: View {
    let stream: AgentStream
    let git: GitInfo?
    let now: Double
    let expanded: Bool
    let t: Theme
    let s: Strings
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: toggle) {
                HStack(spacing: 10) {
                    Circle().fill(t.color(Panel.dot(stream))).frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Panel.title(stream)).fontWeight(.semibold).lineLimit(1).truncationMode(.tail)
                        Text(Panel.stateLine(stream, now: now, s)).font(.system(size: 12)).foregroundStyle(t.g2).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if let c = stream.ctx {
                        Text("\(Int(c.pct.rounded()))%")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(t.color(Panel.ctxLevel(c.pct)))
                    }
                    if !(stream.subs ?? []).isEmpty {
                        SubDots(subs: stream.subs ?? [], t: t)
                    }
                }
                .frame(minHeight: 36)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if expanded { details }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(t.card, in: .rect(cornerRadius: 12))
    }

    @ViewBuilder
    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            if stream.stateKind == .working, let doing = stream.doing {
                kv(s.tr("app.now", fallback: "now"), Panel.actionText(doing, s))
            }
            if let p = stream.plan, let total = p.total, total > 0 {
                kv(s.tr("app.plan", fallback: "plan"), "\(p.done ?? 0)/\(total)" + ((p.now ?? "").isEmpty ? "" : " · \(p.now!)"))
            }
            if let c = stream.ctx {
                Text(ctxText(c)).foregroundStyle(t.g2)
            }
            if let g = git, let branch = g.branch {
                GitLine(git: g, branch: branch, t: t)
            }
            ForEach(stream.subs ?? []) { sub in
                HStack(spacing: 6) {
                    Circle().fill(sub.isWorking ? t.gr : t.g2).frame(width: 6, height: 6)
                    Text(sub.type ?? "agent").fontWeight(.semibold)
                    Text(subText(sub)).foregroundStyle(t.g2).lineLimit(1)
                }
            }
        }
        .font(.system(size: 12))
        .padding(.leading, 20)
    }

    /// "Контекст занят на 72% · сжат в 14:05" (the compaction only within the last hour, like the board).
    private func ctxText(_ c: ContextUse) -> String {
        let pct = Int(c.pct.rounded())
        var line = s.tr("ctx.label", ["n": .number(Double(pct))], fallback: "Context \(pct)%")
        if let cp = stream.compact, now - cp.ts < 3600 {
            let time = Date(timeIntervalSince1970: cp.ts).formatted(date: .omitted, time: .shortened)
            line += " · " + s.tr("ctx.compacted", ["time": .string(time)], fallback: "compacted at \(time)")
        }
        return line
    }

    private func subText(_ sub: Subagent) -> String {
        if sub.isWorking, let d = sub.doing { return Panel.actionText(d, s) }
        if let w = sub.what, !w.isEmpty { return w }
        return sub.isWorking ? s.tr("subs.working", fallback: "working") : s.tr("subs.done", fallback: "done")
    }

    private func kv(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(k).foregroundStyle(t.g2)
            Text(v).lineLimit(2)
        }
    }
}

/// One dot per subagent: filled while working (board: "точки субагентов").
struct SubDots: View {
    let subs: [Subagent]
    let t: Theme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(subs.prefix(8)) { sub in
                Circle()
                    .fill(sub.isWorking ? t.gr : Color.clear)
                    .overlay(Circle().stroke(sub.isWorking ? t.gr : t.g2, lineWidth: 1))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }
}

struct GitLine: View {
    let git: GitInfo
    let branch: String
    let t: Theme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch").foregroundStyle(t.g2)
            Text(branch).lineLimit(1)
            if let d = git.dirty, d > 0 { Text("✎\(d)").foregroundStyle(t.y) }
            if let a = git.ahead, a > 0 { Text("↑\(a)").foregroundStyle(t.g2) }
            if git.ciState != nil { Text("CI").foregroundStyle(t.color(git.ciState)) }
            ForEach(git.prs ?? []) { pr in
                Text("PR #\(pr.n)\(pr.draft == true ? " draft" : "")").foregroundStyle(t.color(pr.checksState))
            }
        }
    }
}

// MARK: - Connection

struct ConnectionLine: View {
    let connection: ConnectionState
    let lastUpdate: Date?
    let strings: Strings
    let theme: Theme

    var body: some View {
        Label(text, systemImage: icon)
            .font(.system(size: 12))
            .foregroundStyle(connection == .live ? theme.g2 : theme.y)
    }

    private var text: String {
        let s = strings
        switch connection {
        case .idle: return s.tr("app.conn.idle", fallback: "Not started")
        case .noToken: return s.tr("app.conn.no_token", fallback: "No token — open Settings")
        case .connecting: return s.tr("app.conn.connecting", fallback: "Connecting…")
        case .live:
            let time = (lastUpdate ?? Date()).formatted(date: .omitted, time: .shortened)
            return s.tr("app.conn.live", ["time": .string(time)], fallback: "updated \(time)")
        case .retrying(let sec, let reason):
            return s.tr("app.conn.retrying", ["s": .number(Double(sec)), "reason": .string(reason)],
                        fallback: "Offline (\(reason)) · retry in \(sec) s")
        case .unauthorized: return s.tr("app.conn.unauthorized", fallback: "Wrong token (401) — check Settings")
        case .notConfigured: return s.tr("app.conn.not_configured", fallback: "The server has no UPTIME_API_TOKEN (503)")
        case .unsupportedAPI(let v):
            return s.tr("app.conn.unsupported", ["v": .number(Double(v))], fallback: "Server API v\(v) is newer — update the app")
        }
    }

    private var icon: String {
        switch connection {
        case .live: return "dot.radiowaves.left.and.right"
        case .connecting, .idle: return "ellipsis"
        default: return "exclamationmark.triangle"
        }
    }
}

extension String {
    /// "ПАСМУРНО" → "пасмурно" → "Пасмурно"
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
