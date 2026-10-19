import 'package:flutter/widgets.dart';

/// Nur im Browser gibt es das iframe (siehe html_question_frame_web.dart);
/// sonst übernimmt die WebView (Android/iOS) oder die Karteikarte.
const bool htmlQuestionFrameSupported = false;

class HtmlQuestionFrame extends StatelessWidget {
  const HtmlQuestionFrame({super.key, required this.page, required this.onMessage, this.onLoaded});

  final String page;
  final void Function(String message) onMessage;
  final VoidCallback? onLoaded;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
