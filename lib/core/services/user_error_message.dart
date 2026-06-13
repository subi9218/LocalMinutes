import 'dart:io';

import '../l10n/app_tr.dart';

/// Converts low-level exceptions into user-facing Korean guidance.
///
/// Keep raw exceptions in CrashLogService. UI should show these messages instead
/// of native/FFI/Dart error strings.
class UserErrorMessage {
  final String title;
  final String message;

  const UserErrorMessage({required this.title, required this.message});

  String get fullText => '$title\n$message';
}

UserErrorMessage friendlyErrorMessage(
  Object error, {
  required String fallbackTitle,
  required String fallbackMessage,
  String? nextStep,
}) {
  final raw = error.toString();
  final lower = raw.toLowerCase();

  UserErrorMessage result;
  if (error is FileSystemException ||
      lower.contains('no space left') ||
      lower.contains('os error: 28') ||
      lower.contains('disk') && lower.contains('space')) {
    result = UserErrorMessage(
      title: tr('저장 공간을 확인해주세요', 'Check your storage space'),
      message: tr(
        '디스크 공간이 부족하거나 파일을 저장할 수 없습니다. '
        '불필요한 파일을 정리한 뒤 다시 시도해주세요.',
        'There is not enough disk space, or the file could not be saved. '
        'Free up some space and try again.',
      ),
    );
  } else if (lower.contains('permission denied') ||
      lower.contains('operation not permitted') ||
      lower.contains('os error: 13') ||
      lower.contains('os error: 1')) {
    result = UserErrorMessage(
      title: tr('권한을 확인해주세요', 'Check your permissions'),
      message: tr(
        '앱이 필요한 파일이나 폴더에 접근하지 못했습니다. '
        '저장 폴더 권한을 확인하거나 다른 폴더를 선택한 뒤 다시 시도해주세요.',
        'The app could not access a required file or folder. '
        'Check the storage folder permissions or choose a different folder, then try again.',
      ),
    );
  } else if (error is SocketException ||
      lower.contains('connection') ||
      lower.contains('network') ||
      lower.contains('timed out')) {
    result = UserErrorMessage(
      title: tr('네트워크를 확인해주세요', 'Check your network'),
      message: tr(
        '인터넷 연결이 불안정하거나 서버에 연결하지 못했습니다. '
        '네트워크 상태를 확인한 뒤 다시 시도해주세요.',
        'Your internet connection is unstable, or the server could not be reached. '
        'Check your network and try again.',
      ),
    );
  } else if (lower.contains('model') ||
      lower.contains('모델') ||
      lower.contains('gguf') ||
      lower.contains('whisper') ||
      lower.contains('llama') ||
      lower.contains('load_stt') ||
      lower.contains('loadllm') ||
      lower.contains('failed to load')) {
    result = UserErrorMessage(
      title: tr('AI 모델을 확인해주세요', 'Check your AI models'),
      message: tr(
        '필요한 음성 인식 또는 요약 모델을 불러오지 못했습니다. '
        '설정에서 모델 설치 상태를 확인한 뒤 다시 시도해주세요.',
        'A required speech recognition or summary model could not be loaded. '
        'Check the model installation status in Settings and try again.',
      ),
    );
  } else if (lower.contains('out of memory') ||
      lower.contains('bad allocation') ||
      lower.contains('memory') ||
      lower.contains('mmap') ||
      lower.contains('metal')) {
    result = UserErrorMessage(
      title: tr('메모리가 부족할 수 있습니다', 'You may be low on memory'),
      message: tr(
        'AI 작업에 필요한 메모리를 확보하지 못했습니다. '
        '다른 앱을 종료한 뒤 다시 시도하거나 더 빠른 모델을 선택해주세요.',
        'Could not allocate the memory needed for the AI task. '
        'Close other apps and try again, or choose a faster model.',
      ),
    );
  } else if (lower.contains('audio') ||
      lower.contains('wav') ||
      lower.contains('오디오') ||
      lower.contains('음성')) {
    result = UserErrorMessage(
      title: tr('오디오 파일을 확인해주세요', 'Check your audio file'),
      message: tr(
        '녹음 파일을 읽거나 처리하지 못했습니다. '
        '파일이 이동되었거나 손상되지 않았는지 확인해주세요.',
        'Could not read or process the recording file. '
        'Make sure the file has not been moved or corrupted.',
      ),
    );
  } else {
    result = UserErrorMessage(title: fallbackTitle, message: fallbackMessage);
  }

  if (nextStep == null || nextStep.trim().isEmpty) return result;
  return UserErrorMessage(
    title: result.title,
    message: '${result.message}\n\n${nextStep.trim()}',
  );
}

String friendlyErrorText(
  Object error, {
  required String fallbackTitle,
  required String fallbackMessage,
  String? nextStep,
}) => friendlyErrorMessage(
  error,
  fallbackTitle: fallbackTitle,
  fallbackMessage: fallbackMessage,
  nextStep: nextStep,
).fullText;
