import SwiftUI

struct PackElementEditorView: View {
  @Binding var element: EditableElement
  var onChange: () -> Void = {}

  var body: some View {
    Form {
      Section("身份") {
        TextField("key（kebab-case）", text: $element.key)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        TextField("名称", text: $element.name)
        Picker("contentRole", selection: $element.contentRole) {
          ForEach(ContentRole.allCases, id: \.self) { role in
            Text(role.rawValue).tag(role)
          }
        }
        Picker("conceptKind", selection: $element.conceptKind) {
          ForEach(ConceptKind.allCases, id: \.self) { kind in
            Text(kind.localizedTitle).tag(kind)
          }
        }
      }

      Section {
        TextEditor(text: $element.introductionText)
          .frame(minHeight: 180)
      } header: {
        Text("介绍")
      } footer: {
        Text("空行分段；图片块：![图注](https://…)")
      }

      Section("来源") {
        ForEach($element.sources) { $source in
          VStack(alignment: .leading, spacing: 8) {
            TextField("标题", text: $source.title)
            TextField("出版方", text: $source.publisher)
            TextField("URL", text: $source.url)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
          }
          .padding(.vertical, 4)
        }
        .onDelete { element.sources.remove(atOffsets: $0) }

        Button {
          element.sources.append(EditableSource())
        } label: {
          Label("添加来源", systemImage: "plus")
        }
      }
    }
    .cultureNavigationTitle(
      element.name.isEmpty ? "编辑元素" : LocalizedStringKey(element.name)
    )
    .onChange(of: element) { _, _ in onChange() }
  }
}

struct PackRelationEditorView: View {
  @Binding var relation: EditableRelation
  let elementKeys: [String]

  var body: some View {
    Form {
      Section("边") {
        elementKeyField("起点 elementKey", text: $relation.elementKey)
        elementKeyField("终点 relatedElementKey", text: $relation.relatedElementKey)
        Picker("kind", selection: $relation.kind) {
          ForEach(RelationKind.allCases, id: \.self) { kind in
            Text(kind.localizedTitle).tag(kind)
          }
        }
        TextField("explanation", text: $relation.explanation, axis: .vertical)
          .lineLimit(3...6)
      }
    }
    .cultureNavigationTitle("编辑关系")
  }

  @ViewBuilder
  private func elementKeyField(_ title: LocalizedStringKey, text: Binding<String>) -> some View {
    if elementKeys.isEmpty {
      TextField(title, text: text)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    } else {
      TextField(title, text: text)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
      ScrollView(.horizontal, showsIndicators: false) {
        HStack {
          ForEach(elementKeys.prefix(24), id: \.self) { key in
            Button(key) { text.wrappedValue = key }
              .font(.caption2)
              .buttonStyle(.bordered)
          }
        }
      }
    }
  }
}

struct PackIntroductionEditorView: View {
  @Binding var introduction: EditableIntroduction

  var body: some View {
    Form {
      Section("绑定") {
        TextField("key", text: $introduction.key)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        TextField("名称", text: $introduction.name)
        TextField("attractionKey", text: $introduction.attractionKey)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        TextField("culturalElementKey", text: $introduction.culturalElementKey)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        TextField("纬度", text: $introduction.latitude)
          .keyboardType(.decimalPad)
        TextField("经度", text: $introduction.longitude)
          .keyboardType(.decimalPad)
        TextField("坐标来源 URL", text: $introduction.coordinateSourceUrl)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
      }
      Section("介绍正文") {
        TextEditor(text: $introduction.introductionText)
          .frame(minHeight: 160)
      }
    }
    .cultureNavigationTitle("编辑介绍")
  }
}

struct PackThemeEditorView: View {
  @Binding var theme: EditableTheme

  var body: some View {
    Form {
      TextField("key", text: $theme.key)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
      TextField("名称", text: $theme.name)
      TextField("摘要", text: $theme.summary, axis: .vertical)
        .lineLimit(2...4)
      TextField("elementKeys（逗号分隔）", text: $theme.elementKeysText, axis: .vertical)
        .lineLimit(2...5)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
      Stepper("minContacted: \(theme.minContacted)", value: $theme.minContacted, in: 1...99)
    }
    .cultureNavigationTitle("编辑主题")
  }
}

struct PackLocaleEditorView: View {
  @Binding var locale: EditableLocaleElement

  var body: some View {
    Form {
      TextField("element key", text: $locale.key)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
      TextField("English name", text: $locale.name)
      Section("English introduction") {
        TextEditor(text: $locale.introductionText)
          .frame(minHeight: 140)
      }
    }
    .cultureNavigationTitle("英文覆盖")
  }
}
