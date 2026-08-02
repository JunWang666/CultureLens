import SwiftUI

struct AskCultureView: View {
    let object: CultureObject?
    @State private var question = ""

    var body: some View {
        ZStack {
            CulturePageBackground()

            VStack(spacing: 24) {
                EditorialHeader(
                    eyebrow: "继续理解",
                    title: object?.canonicalName ?? "文化对象",
                    message: "真实问答服务将在识别算法与知识服务阶段接入。现在可以先体验问题输入的页面结构。"
                )

                VStack(alignment: .leading, spacing: 12) {
                    Text("可以这样问")
                        .font(.headline)
                    suggestion("它为什么会形成这样的结构？")
                    suggestion("在不同地区有什么变化？")
                    suggestion("我还能在哪里看到相似对象？")
                }

                Spacer()

                TextField("问一个关于它的问题", text: $question, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)

                Button("发送") {
                }
                .buttonStyle(.borderedProminent)
                .tint(CultureTheme.cinnabar)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(CultureTheme.pagePadding)
        }
        .navigationTitle("继续追问")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func suggestion(_ text: String) -> some View {
        Button(text) {
            question = text
        }
        .buttonStyle(.bordered)
        .tint(CultureTheme.inkPrimary)
    }
}

#Preview {
    NavigationStack {
        AskCultureView(object: SampleCultureData.featured)
    }
}
