import MapKit
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
  @State private var showsLocationPicker = false

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
      }

      Section {
        if let coordinate = previewCoordinate {
          PackIntroductionCoordinatePreview(coordinate: coordinate, title: previewTitle)
            .id("\(coordinate.latitude),\(coordinate.longitude)")
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)
        }

        TextField("纬度", text: $introduction.latitude)
          .keyboardType(.numbersAndPunctuation)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        TextField("经度", text: $introduction.longitude)
          .keyboardType(.numbersAndPunctuation)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        TextField("坐标来源 URL", text: $introduction.coordinateSourceUrl)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()

        Button {
          showsLocationPicker = true
        } label: {
          Label("在地图上选择", systemImage: "map")
        }
        .accessibilityIdentifier("packEditor.introduction.pickLocation")
      } header: {
        Text("位置")
      } footer: {
        Text("可在地图上搜索或拖动选点；确认后写入经纬度。若坐标来源为空，会填入 Apple 地图链接。")
      }

      Section("介绍正文") {
        TextEditor(text: $introduction.introductionText)
          .frame(minHeight: 160)
      }
    }
    .cultureNavigationTitle("编辑介绍")
    .sheet(isPresented: $showsLocationPicker) {
      PackLocationPickerView(
        initialLatitudeText: introduction.latitude,
        initialLongitudeText: introduction.longitude
      ) { latitude, longitude, appleMapsURL in
        introduction.latitude = latitude
        introduction.longitude = longitude
        if introduction.coordinateSourceUrl
          .trimmingCharacters(in: .whitespacesAndNewlines)
          .isEmpty
        {
          introduction.coordinateSourceUrl = appleMapsURL
        }
      }
    }
  }

  private var previewCoordinate: CLLocationCoordinate2D? {
    guard let coordinate = PackCoordinateFormatting.coordinate(
      latitudeText: introduction.latitude,
      longitudeText: introduction.longitude
    ), !PackCoordinateFormatting.isUnsetOrigin(
      latitude: coordinate.latitude,
      longitude: coordinate.longitude
    ) else { return nil }
    return coordinate
  }

  private var previewTitle: String {
    let name = introduction.name.trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? String(localized: "现场位置") : name
  }
}

private struct PackIntroductionCoordinatePreview: View {
  let coordinate: CLLocationCoordinate2D
  let title: String

  @State private var mapPosition: MapCameraPosition

  init(coordinate: CLLocationCoordinate2D, title: String) {
    self.coordinate = coordinate
    self.title = title
    _mapPosition = State(
      initialValue: .region(
        MKCoordinateRegion(
          center: coordinate,
          latitudinalMeters: 800,
          longitudinalMeters: 800
        )
      )
    )
  }

  var body: some View {
    Map(position: $mapPosition) {
      Marker(title, systemImage: "mappin.circle.fill", coordinate: coordinate)
        .tint(CultureTheme.cinnabar)
    }
    .mapStyle(.standard(elevation: .realistic))
    .frame(height: 160)
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .allowsHitTesting(false)
    .accessibilityLabel(Text("位置预览：\(title)"))
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
