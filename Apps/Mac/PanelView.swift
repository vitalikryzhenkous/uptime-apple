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
        TimelineView(.periodic(from: .now, by: 5)) { ctx in
            let now = store.serverNow(ctx.date)
            let offline = Panel.showsOffline(store.connection, offlineSince: store.offlineSince,
                                             hasData: store.status != nil, now: ctx.date)
            VStack(alignment: .leading, spacing: 10) {
                header(t, s)
                if let st = store.status {
                    if let lim = st.claude?.limits, lim.h5 != nil || lim.d7 != nil {
                        LimitsCard(limits: lim, now: now, t: t, s: s)
                    }
                    sessions(st, now: now, t, s)
                } else {
                    // nothing on screen yet: the connection state is the content
                    ConnectionLine(connection: store.connection, lastUpdate: store.lastUpdate, strings: s, theme: t)
                }
                footer(t, s, offline: offline && store.status != nil)
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
            HStack(spacing: 12) {
                SettingsLink {
                    Image(systemName: "gearshape").foregroundStyle(t.g2)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(",")
                .focusable(false) // the panel opens with no focus ring on it; ⌘, still opens Settings
                .simultaneousGesture(TapGesture().onEnded { NSApp.activate() })
                .help(s.tr("app.settings", fallback: "Settings…"))
                .accessibilityLabel(s.tr("app.settings", fallback: "Settings…"))

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power").foregroundStyle(t.g2)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q")
                .focusable(false)
                .help(s.tr("app.quit", fallback: "Quit"))
                .accessibilityLabel(s.tr("app.quit", fallback: "Quit"))
            }
            .font(.system(size: 14))
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
                    SessionRow(stream: r, git: st.gitInfo(for: r), now: now,
                               expanded: expanded.contains(r.id), t: t, s: s) {
                        if expanded.contains(r.id) { expanded.remove(r.id) } else { expanded.insert(r.id) }
                    }
                }
            }
            // a scroll view would always take its full height; only use one when the list is long
            if rows.count > 6 {
                ScrollView { list }.frame(height: 420)
            } else {
                list
            }
        }
    }

    /// One fixed line: the M920q (CPU and RAM as mini meters, temperature when the server has a sensor) and the weather
    /// with its icon. "Updated hh:mm" is the machine block's tooltip; after the grace period the connection problem
    /// takes the same slot with a retry button. Nothing is inserted or removed, so the window does not jump.
    @ViewBuilder
    private func footer(_ t: Theme, _ s: Strings, offline: Bool) -> some View {
        let st = store.status
        let updated = store.lastUpdate.map {
            s.tr("app.conn.live", ["time": .string($0.formatted(date: .omitted, time: .shortened))],
                 fallback: "updated \($0.formatted(date: .omitted, time: .shortened))")
        } ?? ""
        HStack(spacing: 10) {
            if let m = st?.machine {
                HStack(spacing: 8) {
                    Label("M920Q", systemImage: "desktopcomputer")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    if let cpu = m.cpu { MiniMeter(symbol: "cpu", pct: cpu, t: t, label: "CPU") }
                    if let ram = m.ram { MiniMeter(symbol: "memorychip", pct: ram, t: t, label: "RAM") }
                    if let temp = m.temp {
                        Label("\(Int(temp.rounded()))°", systemImage: "thermometer.medium")
                            .foregroundStyle(temp >= 80 ? t.r : temp >= 65 ? t.y : t.g2)
                    }
                }
                .help(updated)
                .accessibilityElement(children: .combine)
            }
            if offline {
                ConnectionLine(connection: store.connection, lastUpdate: store.lastUpdate, strings: s, theme: t, compact: true)
                Button { store.start() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain)
                    .help(s.tr("app.reconnect", fallback: "Reconnect"))
                    .accessibilityLabel(s.tr("app.reconnect", fallback: "Reconnect"))
            }
            Spacer(minLength: 4)
            if let w = st?.weather, let temp = w.temp {
                let sign = temp > 0 ? "+" : ""
                let word = w.key.map { s.tr($0, fallback: w.text ?? "") } ?? (w.text ?? "")
                HStack(spacing: 4) {
                    Image(systemName: Panel.weatherSymbol(key: w.key, group: w.group, day: w.day ?? true))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 14))
                    Text("\(sign)\(Int(temp))°").fontWeight(.semibold).foregroundStyle(t.fg)
                    if !offline { Text(word.lowercased().capitalizedFirst) }
                }
                .help(word.lowercased().capitalizedFirst)
                .accessibilityElement(children: .combine)
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(t.g2)
        .lineLimit(1)
    }
}

/// An icon with a tiny bar and the percentage: CPU / RAM of the M920q, coloured by load.
struct MiniMeter: View {
    let symbol: String
    let pct: Double
    let t: Theme
    let label: String

    var body: some View {
        let level = Panel.machineLevel(pct)
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 11))
            ZStack(alignment: .leading) {
                Capsule().fill(t.line)
                Capsule().fill(t.color(level)).frame(width: 22 * min(1, max(0, pct / 100)))
            }
            .frame(width: 22, height: 4)
            Text("\(Int(pct.rounded()))%")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(level == .ok ? t.g2 : t.color(level))
        }
        .help("\(label) \(Int(pct.rounded()))%")
        .accessibilityLabel("\(label) \(Int(pct.rounded())) %")
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
            // each window's reset sits on its own row, so "46 min" can't be read as the week's
            if let h5 = limits.h5 {
                bar(s.tr("app.limit.h5", fallback: "5 h"), pct: h5.pct, level: Panel.h5Level(h5.pct), reset: h5.reset)
            }
            if let d7 = limits.d7, Panel.weekIsBig(d7.pct) {
                bar(s.tr("app.limit.week", fallback: "week"), pct: d7.pct, level: Panel.weekLevel(d7.pct), reset: d7.reset)
            } else if let d7 = limits.d7 {
                Text("\(s.tr("app.limit.week", fallback: "week")) \(Int(d7.pct.rounded()))%")
                    .font(.system(size: 12)).foregroundStyle(t.g2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(t.card, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private func bar(_ label: String, pct: Double, level: Level, reset: Double?) -> some View {
        let left = Panel.resetText(reset, now: now, s)
        return HStack(spacing: 8) {
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
            Text(left ?? "")
                .font(.system(size: 11))
                .foregroundStyle(t.g2)
                .lineLimit(1)
                .frame(width: 66, alignment: .trailing)
                .help(left.map { s.tr("app.limit.reset_in", ["t": .string($0)], fallback: "resets in \($0)") } ?? "")
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
    @State private var showAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: toggle) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Panel.title(stream)).fontWeight(.semibold).lineLimit(1).truncationMode(.tail)
                        // the state's colour lives in its words: yellow waiting, red permission, green working
                        Text(Panel.stateLine(stream, now: now, s))
                            .font(.system(size: 12, weight: Panel.dot(stream) == .muted ? .regular : .medium))
                            .foregroundStyle(Panel.dot(stream) == .muted ? t.g2 : t.color(Panel.dot(stream)))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if Panel.showsSubDots(stream) {
                        SubDots(subs: stream.subs ?? [], t: t)
                    }
                    if let c = stream.ctx {
                        ContextRing(pct: c.pct, color: t.color(Panel.ctxLevel(c.pct)), track: t.line)
                            .help(ctxText(c))
                            .accessibilityLabel(ctxText(c))
                    }
                }
                .frame(minHeight: 36)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            // what it waits for: the permission's tool (+ command, opt-in) or the agent's question (opt-in)
            if let ask = Panel.askLine(stream, s) {
                AgentText(text: ask, command: stream.asksPermission, t: t)
                if Panel.showsAll(stream, text: ask) {
                    Button(s.tr("app.pop.show_all", fallback: "Show all ›")) { showAll = true }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(t.b)
                        .popover(isPresented: $showAll, arrowEdge: .leading) {
                            AgentPopover(stream: stream, text: ask, now: now, t: t, s: s)
                        }
                }
            }
            progress
            if Panel.canReply(stream) {
                ReplyBar(stream: stream, t: t, s: s)
            }
            actions

            if expanded { details }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            // the card keeps its own colour; a calm neutral sheen (the theme's text colour, very faint) drifts across
            ZStack {
                t.card
                if let sh = Panel.shimmer(stream) {
                    LightSweep(color: t.fg, shimmer: sh)
                }
            }
        }
        .clipShape(.rect(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }

    /// The agent's plan as a bar with the current step, or — without a plan — time and tool calls in this turn.
    @ViewBuilder
    private var progress: some View {
        if let p = Panel.planProgress(stream) {
            HStack(spacing: 8) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(t.line)
                        Capsule().fill(t.b).frame(width: g.size.width * p.fraction)
                    }
                }
                .frame(width: 70, height: 5)
                Text("\(p.done)/\(p.total)").font(.system(size: 11, weight: .bold, design: .monospaced))
                if let step = p.step {
                    Text(step).font(.system(size: 12)).foregroundStyle(t.g2).lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
        } else if let line = Panel.turnLine(stream, now: now, s), stream.ctx.map({ Panel.ctxLevel($0.pct) == .ok }) ?? true {
            // (with high context the state line already shows "≈N turns", keep the card short)
            Text(line).font(.system(size: 12)).foregroundStyle(t.g2)
        }
    }

    /// CI and PR dots (green / red / grey, yellow while running) that open GitHub, then the session's own links.
    @ViewBuilder
    private var actions: some View {
        let prs = git?.prs ?? []
        let connect = Panel.connectCommand(Prefs.connectTemplate, stream)
        if git != nil || stream.claudeURL != nil || connect != nil {
            HStack(spacing: 10) {
                if let g = git {
                    LinkDot(label: "CI", state: g.ciState, url: g.ciLink, t: t, help: s.tr("app.open_ci", fallback: "Open CI"))
                }
                ForEach(prs) { pr in
                    LinkDot(label: "#\(pr.n)", state: pr.checksState, url: pr.link, t: t,
                            help: s.tr("app.open_pr", fallback: "Open PR") + (pr.title.map { ": \($0)" } ?? ""))
                }
                Spacer(minLength: 0)
                if let url = stream.claudeURL {
                    IconLink(symbol: "bubble.left.and.text.bubble.right", help: s.tr("app.open_claude", fallback: "Open in Claude"),
                             t: t) { NSWorkspace.shared.open(url) }
                }
                if let cmd = connect {
                    IconLink(symbol: "terminal", help: s.tr("app.copy_connect", fallback: "Copy the connect command") + "\n" + cmd,
                             t: t) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(cmd, forType: .string)
                    }
                }
            }
        }
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

/// What the agent waits for: the permission's command (red, monospaced), its question, or the end of its reply —
/// always three lines, so the card never grows over its neighbours; "Show all ›" opens `AgentPopover`.
struct AgentText: View {
    let text: String
    let command: Bool
    let t: Theme

    var body: some View {
        Text(text)
            .font(.system(size: 12, design: command ? .monospaced : .default))
            .foregroundStyle(command ? t.color(.bad) : t.fg)
            .lineLimit(3)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The agent's whole text beside the panel (up to 600 characters, paragraphs kept), scrollable and selectable;
/// under it the reply field — or, while a dialog is open, the question's options to read and a way to the terminal.
struct AgentPopover: View {
    let stream: AgentStream
    let text: String
    let now: Double
    let t: Theme
    let s: Strings
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(stream.project).font(.system(size: 15, weight: .bold))
                    Text(Panel.stateLine(stream, now: now, s))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(t.color(Panel.dot(stream)))
                }
                Spacer(minLength: 0)
                Button(copied ? s.tr("app.pop.copied", fallback: "Copied") : s.tr("app.pop.copy", fallback: "Copy")) {
                    copy(text)
                    copied = true
                }
                .controlSize(.small)
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(t.g2)
                    .frame(width: 22, height: 22)
                    .help(s.tr("app.pop.close", fallback: "Close"))
                    .accessibilityLabel(s.tr("app.pop.close", fallback: "Close"))
            }

            ScrollView {
                Text(text)
                    .font(.system(size: 13, design: stream.asksPermission ? .monospaced : .default))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(maxHeight: 280)
            .fixedSize(horizontal: false, vertical: true)
            .background(t.line.opacity(0.35), in: .rect(cornerRadius: 10))

            let options = Panel.questionOptions(stream)
            if !options.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(s.tr("app.pop.options", fallback: "Options (pick in the terminal)"))
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(t.g2)
                    ForEach(Array(options.enumerated()), id: \.offset) { i, label in
                        Text("\(i + 1) · \(label)")
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(t.line))
                    }
                }
            }

            switch Panel.popoverMode(stream) {
            case .reply:
                ReplyBar(stream: stream, t: t, s: s)
                Text(s.tr("app.pop.hint", fallback: "Enter — send · Esc — close"))
                    .font(.system(size: 11)).foregroundStyle(t.g2)
            case .readOnly:
                HStack(alignment: .center, spacing: 8) {
                    Text(s.tr("app.pop.locked",
                              fallback: "Replying from the panel is off: in an open dialog a typed digit would pick an option."))
                        .font(.system(size: 12)).foregroundStyle(t.g2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if let cmd = Panel.connectCommand(Prefs.connectTemplate, stream) {
                        Button(s.tr("app.pop.open_terminal", fallback: "Open Terminal")) { openTerminal(cmd) }
                            .controlSize(.regular)
                            .help(s.tr("app.pop.open_terminal_help",
                                       fallback: "Copies the connect command and opens Terminal — paste it with ⌘V"))
                    }
                }
            case .text:
                EmptyView()
            }
        }
        .padding(16)
        .frame(width: 380)
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    /// App Store sandbox: the app may open Terminal but not drive it, so the command goes to the clipboard first.
    private func openTerminal(_ cmd: String) {
        copy(cmd)
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.openApplication(at: terminal, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// A one-line reply to the waiting agent — and /compact once the context is ≥70 % full. The board types it into
/// the session's tmux pane (`POST /api/v1/sessions/<id>/input`); it checks the rules again and refuses with a reason.
struct ReplyBar: View {
    let stream: AgentStream
    let t: Theme
    let s: Strings
    @State private var draft = ""
    @State private var sending = false
    @State private var note: Note?

    struct Note: Equatable { let text: String; let ok: Bool }

    private var problem: AgentInput.Problem? { AgentInput.problem(draft) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                TextField(s.tr("app.reply.placeholder", fallback: "Reply to the agent…"), text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(t.line.opacity(0.5), in: .rect(cornerRadius: 7))
                    .disabled(sending)
                    .onSubmit { send(.reply(draft)) }
                    .onChange(of: draft) { _, new in if !new.isEmpty { note = nil } } // typing again hides "Sent"
                Button { send(.reply(draft)) } label: {
                    Image(systemName: sending ? "ellipsis.circle" : "arrow.up.circle.fill").font(.system(size: 17))
                }
                .buttonStyle(.plain)
                .foregroundStyle(problem == nil && !sending ? t.b : t.g2)
                .disabled(problem != nil || sending)
                .help(s.tr("app.reply.send", fallback: "Send to the agent"))
                .accessibilityLabel(s.tr("app.reply.send", fallback: "Send to the agent"))
                if Panel.offersCompact(stream) {
                    Button { send(.compact) } label: {
                        Text("/compact").font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .overlay(Capsule().stroke(t.color(.warn).opacity(0.7)))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(t.color(.warn))
                    .disabled(sending)
                    .help(s.tr("app.reply.compact_help", fallback: "Compact the context: sends /compact"))
                }
            }
            if let note {
                Text(note.text).font(.system(size: 11)).foregroundStyle(note.ok ? t.gr : t.color(.bad)).lineLimit(1)
            } else if let p = problem, p != .empty {
                Text(Panel.inputErrorText(p.rawValue, s)).font(.system(size: 11)).foregroundStyle(t.g2).lineLimit(1)
            }
        }
    }

    private func send(_ input: AgentInput) {
        if case .reply = input, problem != nil { return }
        guard let id = stream.session, let client = Prefs.makeClient(), !sending else { return }
        sending = true
        note = nil
        Task { @MainActor in
            defer { sending = false }
            do {
                switch try await client.send(input, to: id) {
                case .sent:
                    if case .reply = input { draft = "" }
                    note = Note(text: s.tr("app.reply.sent", fallback: "Sent"), ok: true)
                case .refused(let code):
                    note = Note(text: Panel.inputErrorText(code, s), ok: false)
                }
            } catch {
                note = Note(text: Panel.inputErrorText("network", s), ok: false)
            }
        }
    }
}

/// A soft band of light in the state's colour that drifts across the card from left to right, then rests
/// (`Panel.shimmer`). Nothing moves with Reduce Motion — the card keeps only its tint.
struct LightSweep: View {
    let color: Color
    let shimmer: Panel.Shimmer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
                GeometryReader { g in
                    if let x = Panel.shimmerPosition(shimmer, at: ctx.date.timeIntervalSinceReferenceDate) {
                        let band = g.size.width * 0.45
                        LinearGradient(colors: [color.opacity(0), color.opacity(shimmer.strength), color.opacity(0)],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: band, height: g.size.height * 2)
                            .rotationEffect(.degrees(18)) // a slanted sheen reads as light, not a bar
                            .position(x: -band / 2 + (g.size.width + band) * x, y: g.size.height / 2)
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// A status dot with a short label ("CI", "#12"): green ok, red fail, yellow running, grey unknown; opens GitHub.
struct LinkDot: View {
    let label: String
    let state: CheckState?
    let url: URL?
    let t: Theme
    let help: String

    var body: some View {
        Button {
            if let url { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: 4) {
                Circle().fill(t.color(state)).frame(width: 8, height: 8)
                Text(label).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(t.g2)
            }
            .frame(minHeight: 22)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(url == nil)
        .help(help)
        .accessibilityLabel("\(label) \(state?.rawValue ?? "")")
    }
}

/// A small icon button with a tooltip.
struct IconLink: View {
    let symbol: String
    let help: String
    let t: Theme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(t.g2).frame(minWidth: 22, minHeight: 22)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
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
            // CI and PRs are the dots on the card itself
        }
    }
}

// MARK: - Connection

/// Context use as a ring, like the board's card: the arc and the number in the level's colour.
struct ContextRing: View {
    let pct: Double
    let color: Color
    let track: Color

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: 3)
            Circle()
                .trim(from: 0, to: min(1, max(0, pct / 100)))
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(pct.rounded()))")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .frame(width: 28, height: 28)
    }
}

struct ConnectionLine: View {
    let connection: ConnectionState
    let lastUpdate: Date?
    let strings: Strings
    let theme: Theme
    /// In the footer: only the reason ("connection lost"), the rest is implied by the warning colour.
    var compact = false

    var body: some View {
        Label(compact ? short : text, systemImage: icon)
            .font(.system(size: 12))
            .foregroundStyle(connection == .live ? theme.g2 : theme.y)
            .lineLimit(1)
            .help(text)
    }

    private var short: String {
        if case .retrying(_, let reason) = connection { return reason }
        return text
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
