import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 앱 전역 Riverpod 컨테이너.
///
/// 위젯이 dispose된 뒤 완료되는 긴 비동기 작업(모델 로드·요약·정지 마무리)의
/// continuation은 ConsumerState.ref를 쓸 수 없다(StateError). 그런 곳에서
/// provider 상태를 안전하게 정리(예: isSummarizingProvider /
/// nativeRecordingActiveProvider 해제, meetingsProvider 갱신)할 수 있도록
/// 컨테이너를 전역으로 둔다. main.dart의 UncontrolledProviderScope가
/// 이 컨테이너를 위젯 트리와 공유하므로 ref와 같은 상태를 가리킨다.
final globalProviderContainer = ProviderContainer();
