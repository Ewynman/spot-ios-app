// import SwiftUI

// struct DebugPerfOverlay: View {
//     @State private var isVisible = false

//     var body: some View {
//         VStack(alignment: .leading, spacing: 4) {
//             Text("Perf").font(.caption).bold().foregroundColor(.white)
//             HStack { Text("t_first_item:").foregroundColor(.white); Text(fmt(PerfMetrics.shared.measure("t_first_item"))).foregroundColor(.white) }.font(.caption2)
//             HStack { Text("img_first_paint:").foregroundColor(.white); Text(fmt(PerfMetrics.shared.value("img_first_paint") )).foregroundColor(.white) }.font(.caption2)
//         }
//         .padding(8)
//         .background(Color.black.opacity(0.6))
//         .cornerRadius(8)
//         .padding(12)
//         .opacity(isVisible ? 1 : 0)
//         .onTapGesture { withAnimation { isVisible.toggle() } }
//         .onAppear { withAnimation { isVisible = true } }
//     }

//     private func fmt(_ t: TimeInterval?) -> String { guard let t else { return "-" }; return String(format: "%.2fs", t) }
//     private func fmt2(_ v: Double?) -> String { guard let v else { return "-" }; return String(format: "%.2fs", v) }
// }


