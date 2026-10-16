import SwiftUI

/// the desk: rail on the left, the main glass card with the top bar, the transcript, the side panel and the status line
struct RootView: View {
    @EnvironmentObject var desk: DeskModel
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Rail().frame(width: 232)
            ZStack {
                RoundedRectangle(cornerRadius: 29, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x222222), Color(hex: 0x1e1e1e)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: 29, style: .continuous).fill(RadialGradient(colors: [Color.white.opacity(0.055), .clear], center: UnitPoint(x: 0.48, y: -0.08), startRadius: 0, endRadius: 760)))
                    .overlay(RoundedRectangle(cornerRadius: 29, style: .continuous).strokeBorder(Color.white.opacity(0.03)))
                VStack(spacing: 0) {
                    TopBar().frame(height: 84)
                    HStack(spacing: 0) {
                        CenterPane().frame(maxWidth: .infinity)
                        if desk.folder != nil { SidePanel().frame(width: 460).padding([.trailing, .bottom], 14) }
                    }
                    StatusBar().frame(height: 34)
                }
                .clipShape(RoundedRectangle(cornerRadius: 29, style: .continuous))
                if let t = desk.toast {
                    Text(t).font(Theme.sans(12.5)).foregroundStyle(Color(hex: 0xe6e6e6)).padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Capsule().fill(Color(hex: 0x2c2c2c))).overlay(Capsule().strokeBorder(Color.white.opacity(0.1)))
                        .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom).padding(.bottom, 52)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.2), value: desk.toast)
        }
        .padding(18)
        .background(Theme.bg)
        .ignoresSafeArea()
    }
}

struct CenterPane: View {
    @EnvironmentObject var desk: DeskModel
    var body: some View {
        VStack(spacing: 0) {
            if desk.turns.isEmpty { Welcome() } else {
                Transcript()
                if !desk.jobs.isEmpty { JobsBar().padding(.horizontal, 26).padding(.bottom, 8) }
                Composer().padding(.horizontal, 26).padding(.bottom, 16)
            }
        }
    }
}

/// background jobs the agent started: dev servers, watchers, long runs; they outlive the turn
struct JobsBar: View {
    @EnvironmentObject var desk: DeskModel
    @State private var openId: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("JOBS").font(Theme.mono(10, .medium)).tracking(1.4).foregroundStyle(Color(hex: 0x6e6e6e))
                ForEach(desk.jobs) { j in JobChip(job: j, open: openId == j.id) { openId = openId == j.id ? nil : j.id } }
                Spacer()
                if desk.jobs.contains(where: { $0.status != "running" }) { Button("clear") { desk.clearJobs() }.buttonStyle(Quiet()).font(Theme.mono(10)).foregroundStyle(Color(hex: 0x7a7a7a)) }
            }
            if let id = openId, let j = desk.jobs.first(where: { $0.id == id }) { JobTail(job: j) }
        }
    }
}
struct JobChip: View {
    @ObservedObject var job: Job; var open: Bool; var tap: () -> Void
    @EnvironmentObject var desk: DeskModel
    var color: Color { job.status == "running" ? Theme.green : job.status == "failed" ? Theme.red : Color(hex: 0x7a7a7a) }
    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(job.command).font(Theme.mono(11)).foregroundStyle(Color(hex: 0xcfcfcf)).lineLimit(1).frame(maxWidth: 220)
            Text(job.status == "running" ? ago(job.started) : job.status + (job.exit.map { " \($0)" } ?? "")).font(Theme.mono(10)).foregroundStyle(Color(hex: 0x7a7a7a))
            if job.status == "running" { Button { desk.stopJob(job) } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(Color(hex: 0x9a9a9a)) }.buttonStyle(Quiet()).help("Stop") }
        }
        .padding(.horizontal, 10).frame(height: 26)
        .background(Capsule().fill(Color.white.opacity(open ? 0.09 : 0.05))).overlay(Capsule().strokeBorder(Color.white.opacity(0.07)))
        .contentShape(Capsule()).onTapGesture(perform: tap)
    }
}
struct JobTail: View {
    @ObservedObject var job: Job
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView { Text(job.tail.isEmpty ? "no output yet" : job.tail.suffix(200).joined(separator: "\n")).font(Theme.mono(11)).foregroundStyle(Color(hex: 0x9a9a9a)).lineSpacing(2).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(10); Color.clear.frame(height: 1).id("t") }
                .onChange(of: job.tail.count) { _, _ in proxy.scrollTo("t") }
        }
        .frame(height: 140)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.4)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.06)))
    }
}
