import '../services/app_settings.dart';

/// 경량 다국어 헬퍼.
///
/// 별도 .arb 카탈로그 없이 호출 지점에서 한국어/영어 문자열을 직접 제공한다.
/// 리뷰 통과 경로(온보딩·모델 준비·녹음·요약)를 우선 다국어화하기 위한 최소 구현.
///
/// 예) Text(tr('앱 시작', 'Start app'))
String tr(String ko, String en) =>
    AppSettings.instance.effectiveLanguageCode == 'en' ? en : ko;

/// 현재 적용 언어가 영어인지.
bool get isEn => AppSettings.instance.effectiveLanguageCode == 'en';
