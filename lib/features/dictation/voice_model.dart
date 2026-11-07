/// The voice models of the dictation (SPEC-040 R7). The files come from one
/// fixed revision, so the `sha256` below never changes under the app.
enum VoiceModel {
  quality(
    file: 'ggml-small-q5_1.bin',
    bytes: 190085487,
    sha256: 'ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb',
    label: 'Melhor qualidade',
    detail: '190 MB · mais lento',
    size: '190 MB',
  ),
  fast(
    file: 'ggml-base-q5_1.bin',
    bytes: 59707625,
    sha256: '422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898',
    label: 'Mais rápido',
    detail: '60 MB · menos preciso',
    size: '60 MB',
  );

  const VoiceModel({
    required this.file,
    required this.bytes,
    required this.sha256,
    required this.label,
    required this.detail,
    required this.size,
  });

  static const _revision = '5359861c739e955e79d9a303bcbc70fb988958b1';

  final String file;
  final int bytes;
  final String sha256;
  final String label;
  final String detail;
  final String size;

  Uri get url => Uri.parse(
    'https://huggingface.co/ggerganov/whisper.cpp/resolve/$_revision/$file',
  );
}

/// `--language` of the transcription.
enum VoiceLanguage {
  portuguese('pt', 'Português'),
  auto('auto', 'Detectar automaticamente');

  const VoiceLanguage(this.code, this.label);

  final String code;
  final String label;
}
