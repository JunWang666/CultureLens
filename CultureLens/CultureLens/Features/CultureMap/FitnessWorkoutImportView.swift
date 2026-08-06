import SwiftUI

struct FitnessWorkoutImportView: View {
  private enum LoadState {
    case idle
    case loading
    case loaded([FitnessWorkoutSummary])
    case failed(String)
  }

  private struct ImportNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
  }

  @Environment(\.dismiss) private var dismiss

  let onImported: ([ImportedTrack]) -> Void

  @State private var loadState: LoadState = .idle
  @State private var selectedWorkoutIDs: Set<UUID> = []
  @State private var importedSourceIdentifiers: Set<String>
  @State private var isImporting = false
  @State private var completedImportCount = 0
  @State private var importNotice: ImportNotice?

  init(
    importedSourceIdentifiers: Set<String>,
    onImported: @escaping ([ImportedTrack]) -> Void
  ) {
    _importedSourceIdentifiers = State(initialValue: importedSourceIdentifiers)
    self.onImported = onImported
  }

  var body: some View {
    NavigationStack {
      content
        .navigationTitle("从 Fitness 导入")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("取消") { dismiss() }
              .disabled(isImporting)
          }
          ToolbarItem(placement: .confirmationAction) {
            Button(isImporting ? "正在导入…" : "导入") {
              importSelectedWorkouts()
            }
            .disabled(selectedWorkoutIDs.isEmpty || isImporting)
          }
        }
    }
    .interactiveDismissDisabled(isImporting)
    .task {
      await loadWorkouts()
    }
    .alert(item: $importNotice) { notice in
      Alert(
        title: Text(notice.title),
        message: Text(notice.message),
        dismissButton: .default(Text("好"))
      )
    }
  }

  @ViewBuilder
  private var content: some View {
    switch loadState {
    case .idle, .loading:
      VStack(spacing: 14) {
        ProgressView()
        Text("正在读取带路线的运动记录…")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

    case .failed(let message):
      ContentUnavailableView {
        Label("无法读取 Fitness 记录", systemImage: "heart.slash")
      } description: {
        Text(message)
      } actions: {
        Button("重试") {
          Task { await loadWorkouts() }
        }
        .buttonStyle(.borderedProminent)
      }

    case .loaded(let workouts):
      if workouts.isEmpty {
        ContentUnavailableView {
          Label("没有可导入的路线", systemImage: "figure.run")
        } description: {
          Text("只会显示当前健康权限可读取、并且带 GPS 路线的运动记录。你也可以在健康 App 中检查 CultureLens 的访问权限。")
        } actions: {
          Button("重新读取") {
            Task { await loadWorkouts() }
          }
          .buttonStyle(.borderedProminent)
        }
      } else {
        workoutList(workouts)
      }
    }
  }

  private func workoutList(_ workouts: [FitnessWorkoutSummary]) -> some View {
    List {
      Section {
        Text("CultureLens 只读取你选择的路线，并把副本保存在 App 内；不会修改 Fitness 或健康中的原记录。")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      Section("带路线的运动记录") {
        ForEach(workouts) { workout in
          workoutRow(workout)
        }
      }

      if isImporting {
        Section {
          HStack(spacing: 12) {
            ProgressView()
            Text("正在导入 \(completedImportCount)/\(selectedWorkoutIDs.count)…")
              .foregroundStyle(.secondary)
          }
        }
      }
    }
    .refreshable {
      guard !isImporting else { return }
      await loadWorkouts()
    }
  }

  private func workoutRow(_ workout: FitnessWorkoutSummary) -> some View {
    let sourceIdentifier = workout.id.uuidString.lowercased()
    let isAlreadyImported = importedSourceIdentifiers.contains(sourceIdentifier)
    let isSelected = selectedWorkoutIDs.contains(workout.id)

    return Button {
      guard !isAlreadyImported, !isImporting else { return }
      if isSelected {
        selectedWorkoutIDs.remove(workout.id)
      } else {
        selectedWorkoutIDs.insert(workout.id)
      }
    } label: {
      HStack(spacing: 12) {
        Image(systemName: activitySymbol(for: workout.activityTitle))
          .font(.title3)
          .foregroundStyle(CultureTheme.cinnabar)
          .frame(width: 28)

        VStack(alignment: .leading, spacing: 4) {
          Text(workout.activityTitle)
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
          Text(workout.startedAt, format: .dateTime.year().month().day().hour().minute())
            .font(.subheadline)
            .foregroundStyle(.secondary)
          HStack(spacing: 5) {
            Text(durationText(workout.duration))
            Text("·")
            Text(workout.sourceName)
              .lineLimit(1)
          }
          .font(.caption)
          .foregroundStyle(.tertiary)
        }

        Spacer(minLength: 8)

        if isAlreadyImported {
          Label("已导入", systemImage: "checkmark.circle.fill")
            .labelStyle(.iconOnly)
            .foregroundStyle(.secondary)
            .accessibilityLabel("已导入")
        } else {
          Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(isSelected ? CultureTheme.cinnabar : .secondary)
            .accessibilityLabel(isSelected ? "已选择" : "未选择")
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(isAlreadyImported || isImporting)
    .accessibilityHint(isAlreadyImported ? "这条运动路线已经保存在 App 中" : "双击切换选择状态")
  }

  private func loadWorkouts() async {
    guard !isImporting else { return }
    loadState = .loading
    do {
      let workouts = try await FitnessWorkoutRouteService.shared.loadRoutableWorkouts()
      guard !Task.isCancelled else { return }
      selectedWorkoutIDs = selectedWorkoutIDs.intersection(Set(workouts.map(\.id)))
      loadState = .loaded(workouts)
    } catch is CancellationError {
      return
    } catch {
      loadState = .failed(error.localizedDescription)
    }
  }

  private func importSelectedWorkouts() {
    guard case .loaded(let workouts) = loadState else { return }
    let selected = workouts.filter { selectedWorkoutIDs.contains($0.id) }
    guard !selected.isEmpty else { return }

    isImporting = true
    completedImportCount = 0

    Task {
      var imported: [ImportedTrack] = []
      var failures: [String] = []

      for workout in selected {
        do {
          let draft = try await FitnessWorkoutRouteService.shared.routeDraft(for: workout)
          let track = try await ImportedTrackStore.shared.importFitnessWorkout(draft)
          imported.append(track)
          importedSourceIdentifiers.insert(workout.id.uuidString.lowercased())
        } catch is CancellationError {
          isImporting = false
          return
        } catch {
          failures.append("\(workout.activityTitle)：\(error.localizedDescription)")
        }
        completedImportCount += 1
      }

      isImporting = false
      let importedWorkoutIDs = Set(
        imported.compactMap { track in
          track.sourceIdentifier.flatMap(UUID.init(uuidString:))
        }
      )
      selectedWorkoutIDs.subtract(importedWorkoutIDs)

      if !imported.isEmpty {
        onImported(imported)
      }

      if failures.isEmpty {
        dismiss()
      } else {
        importNotice = ImportNotice(
          title: imported.isEmpty ? String(localized: "无法导入轨迹") : String(localized: "部分轨迹已导入"),
          message: failures.prefix(3).joined(separator: "\n")
        )
      }
    }
  }

  private func durationText(_ duration: TimeInterval) -> String {
    let totalMinutes = max(Int(duration / 60), 1)
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    if hours == 0 {
      return String(localized: "\(minutes) 分钟")
    }
    if minutes == 0 {
      return String(localized: "\(hours) 小时")
    }
    return String(localized: "\(hours) 小时 \(minutes) 分钟")
  }

  private func activitySymbol(for title: String) -> String {
    if title == String(localized: "户外骑行") { return "bicycle" }
    if title == String(localized: "户外步行") { return "figure.walk" }
    if title == String(localized: "徒步") { return "figure.hiking" }
    if title == String(localized: "游泳") { return "figure.pool.swim" }
    return "figure.run"
  }
}
