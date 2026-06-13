import '../services/app_settings.dart';

/// 경량 다국어 헬퍼.
///
/// 별도 .arb 카탈로그 없이 호출 지점에서 한국어/영어 문자열을 직접 제공한다.
/// 리뷰 통과 경로(온보딩·모델 준비·녹음·요약)를 우선 다국어화하기 위한 최소 구현.
///
/// 예) Text(tr('앱 시작', 'Start app'))
///
/// AppSettings가 아직 초기화되지 않은 경우(예: 단위 테스트, 앱 부팅 극초기)에는
/// 기본 언어인 한국어로 안전하게 폴백한다.
String tr(String ko, String en) {
  try {
    return AppSettings.instance.effectiveLanguageCode == 'en' ? en : ko;
  } catch (_) {
    return ko;
  }
}

/// 현재 적용 언어가 영어인지. (미초기화 시 false)
bool get isEn {
  try {
    return AppSettings.instance.effectiveLanguageCode == 'en';
  } catch (_) {
    return false;
  }
}
