import SwiftUI

struct StatusBar: View {
    @EnvironmentObject var desk: DeskModel
    var body: some View {
        HStack(spacing: 10) {
            Text("■").foregroundStyle(Theme.green)
            Text("build")
            Sep()
            Text(desk.served ?? (desk.currentModel?.label ?? desk.model).lowercased())
            Sep()
            Text((KIND_LABEL[desk.kind] ?? desk.kind).lowercased())
            Spacer()
            Text(desk.turnsLeft.map { "\($0) free turns left today" } ?? "\(desk.freeTurns) free turns a day")
            Sep()
            Key("enter"); Text("send")
            Key("shift+enter"); Text("newline")
            Key("/"); Text("commands")
        }
        .font(Theme.mono(11)).foregroundStyle(Color(hex: 0x8c8c8c))
        .padding(.horizontal, 22)
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1) }
    }
}
struct Sep: View { var body: some View { Text("·").foregroundStyle(Color(hex: 0x4a4a4a)) } }
struct Key: View {
    var k: String
    init(_ k: String) { self.k = k }
    var body: some View {
        Text(k).font(Theme.mono(10)).foregroundStyle(Color(hex: 0xb0b0b0)).padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.06))).overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white.opacity(0.08)))
    }
}
