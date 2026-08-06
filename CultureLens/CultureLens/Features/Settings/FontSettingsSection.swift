import SwiftUI

/// 设置页：字族 + 字号。栏目头本身即预览，不再单独放样例块。
struct FontSettingsSection: View {
  @Environment(TypographyPreferenceStore.self) private var typographyStore

  var body: some View {
    @Bindable var typographyStore = typographyStore

    VStack(alignment: .leading, spacing: 14) {
      MagazineSectionHeader(
        eyebrow: "TYPE",
        "字体",
        subtitle: "调整后会立刻作用到全文阅读界面。"
      )

      VStack(alignment: .leading, spacing: 8) {
        Text("字族")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(CultureTheme.inkPrimary)

        Picker("字族", selection: $typographyStore.family) {
          ForEach(TypographyFamilyPreference.allCases) { family in
            Text(family.title).tag(family)
          }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("typography.familyPicker")

        Text(typographyStore.family.detail)
          .font(CultureTypography.meta(.caption))
          .foregroundStyle(CultureTheme.inkSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("字号")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(CultureTheme.inkPrimary)

        Picker("字号", selection: $typographyStore.size) {
          ForEach(TypographySizePreference.allCases) { size in
            Text(size.title).tag(size)
          }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("typography.sizePicker")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
