import 'package:flutter/foundation.dart';

/// 현재 진행 중인 무거운 작업(전사/요약) 한 건의 상태.
@immutable
class ProcessingJob {
  /// 작업 고유 식별자 — update의 copyWith를 거쳐도 유지되며,
  /// clearIf가 "같은 작업"인지 판정하는 기준.
  final Object token;

  /// 대상 회의 ID.
  final int meetingId;

  /// 'transcribe' | 'summarize'
  final String kind;

  /// 회의 제목(배너 표시용). 비어 있을 수 있음.
  final String meetingTitle;

  /// 현지화된 진행 상태 문구.
  final String label;

  /// 0.0~1.0 진행률. 음수이면 비확정(indeterminate).
  final double progress;

  const ProcessingJob({
    required this.token,
    required this.meetingId,
    required this.kind,
    required this.meetingTitle,
    required this.label,
    this.progress = -1,
  });

  ProcessingJob copyWith({String? label, double? progress}) => ProcessingJob(
    token: token,
    meetingId: meetingId,
    kind: kind,
    meetingTitle: meetingTitle,
    label: label ?? this.label,
    progress: progress ?? this.progress,
  );
}

/// 앱 전역의 "지금 무거운 작업(전사/요약)이 진행 중" 상태를 보관한다.
///
/// 전사/요약은 단일 온디바이스 모델·메모리 예산상 동시에 하나만 가능하므로,
/// 이 상태로 (1) 충돌하는 작업 시작을 막고(게이팅), (2) 어느 화면에서든 진행
/// 상황을 보여주며(영구 배너), (3) 화면을 옮겼다 돌아와도 진행을 잃지 않게 한다.
///
/// 위젯 생명주기와 무관하게 갱신해야 하므로(작업 중 다른 회의로 이동 시 위젯이
/// dispose될 수 있음) Riverpod ref가 아니라 싱글턴 + ValueNotifier로 둔다.
class ProcessingStatus {
  ProcessingStatus._();
  static final ProcessingStatus instance = ProcessingStatus._();

  /// 현재 작업. 없으면 null.
  final ValueNotifier<ProcessingJob?> active = ValueNotifier<ProcessingJob?>(
    null,
  );

  /// 작업이 끝날 때마다 증가하는 신호. 끝난 작업의 회의 데이터를 새로고침할 때 쓴다.
  /// (작업 위젯이 화면 이탈로 dispose되면 위젯 안의 invalidate가 실행되지 않으므로,
  ///  화면에 상주하는 HomeScreen이 이 신호를 듣고 대신 새로고침한다.)
  final ValueNotifier<int> completionTick = ValueNotifier<int>(0);

  /// 마지막으로 끝난 작업(새로고침 대상 식별용).
  ProcessingJob? lastCompleted;

  /// 현재 작업을 중지하는 콜백. 작업 소유 위젯이 등록한다(화면을 떠나도 동작).
  VoidCallback? _onCancel;

  bool get isBusy => active.value != null;

  /// 현재 작업을 중지할 수 있는지(콜백 등록 여부).
  bool get cancelable => _onCancel != null;

  /// 새 작업 시작을 알린다. 시작된 작업 객체를 반환하며, 호출자는 이 객체로
  /// [clearIf]를 호출해 "자기 작업일 때만" 종료 처리해야 한다.
  /// (게이트 공백으로 중복 시작이 발생해도, 먼저 끝난 작업의 clear가
  ///  진행 중인 다른 작업의 배너·게이트를 지우지 못하게 하는 안전선)
  ProcessingJob start({
    required int meetingId,
    required String kind,
    required String meetingTitle,
    required String label,
    double progress = -1,
  }) {
    final job = ProcessingJob(
      token: Object(),
      meetingId: meetingId,
      kind: kind,
      meetingTitle: meetingTitle,
      label: label,
      progress: progress,
    );
    active.value = job;
    return job;
  }

  /// [job]이 여전히 현재 작업일 때만 종료 처리한다.
  /// 다른 작업이 이미 자리를 차지했다면 아무것도 하지 않는다.
  void clearIf(ProcessingJob job) {
    if (active.value?.token == job.token) clear();
  }

  /// 진행 상태/진행률 갱신 (현재 작업이 있을 때만).
  void update({String? label, double? progress}) {
    final cur = active.value;
    if (cur == null) return;
    active.value = cur.copyWith(label: label, progress: progress);
  }

  /// 중지 콜백 등록. 작업 시작 직후 호출한다.
  void registerCancel(VoidCallback onCancel) {
    _onCancel = onCancel;
  }

  /// 현재 작업 중지 요청(배너의 '중지' 버튼 등에서 호출). 위젯 생명주기와 무관.
  void requestCancel() {
    _onCancel?.call();
  }

  /// 작업 종료를 알린다. 끝난 작업을 기록하고 완료 신호를 발생시킨다.
  void clear() {
    final cur = active.value;
    _onCancel = null;
    active.value = null;
    if (cur != null) {
      lastCompleted = cur;
      completionTick.value++;
    }
  }
}
