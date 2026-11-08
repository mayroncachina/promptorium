import 'package:flutter/foundation.dart';

/// A version `1.2.3`, `v1.2.3-beta.1` (SPEC-044 R2, R5).
@immutable
class SemVer implements Comparable<SemVer> {
  const SemVer(this.major, this.minor, this.patch, [this.suffix = '']);

  final int major, minor, patch;

  /// What comes after the core (`-beta.1`, `+build`), empty for none.
  final String suffix;

  static final _pattern = RegExp(
    r'^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)([-+.~][0-9A-Za-z.+~-]*)?$',
  );

  /// Null when [text] is not a version (a tag `release-1`, `1.2`).
  static SemVer? tryParse(String text) {
    final m = _pattern.firstMatch(text.trim());
    if (m == null) return null;
    return SemVer(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      m.group(4) ?? '',
    );
  }

  /// A pre-release (`-beta`): lower than the same core without it.
  bool get isPrerelease => suffix.startsWith('-') || suffix.startsWith('~');

  SemVer bumpMajor() => SemVer(major + 1, 0, 0);
  SemVer bumpMinor() => SemVer(major, minor + 1, 0);
  SemVer bumpPatch() => SemVer(major, minor, patch + 1);

  @override
  int compareTo(SemVer other) {
    for (final (a, b) in [
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
    ]) {
      if (a != b) return a.compareTo(b);
    }
    if (isPrerelease != other.isPrerelease) return isPrerelease ? -1 : 1;
    return suffix.compareTo(other.suffix);
  }

  bool operator >(SemVer other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) =>
      other is SemVer && compareTo(other) == 0 && other.suffix == suffix;

  @override
  int get hashCode => Object.hash(major, minor, patch, suffix);

  /// `1.2.3` (without `v`).
  @override
  String toString() => '$major.$minor.$patch$suffix';
}

/// Whether a tag looks like a version: `v1.2.3` or `1.2.3`, with an
/// optional suffix (R2).
bool isVersionTag(String tag) => SemVer.tryParse(tag) != null;

/// The tag of [version] in the style of the repository: with `v` when the
/// last tag has one, or when there is no tag yet.
String tagFor(String version, {String? lastTag}) {
  final v = version.trim().replaceFirst(RegExp('^v'), '');
  return lastTag == null || lastTag.startsWith('v') ? 'v$v' : v;
}

/// Why [input] can't be the new version (null = valid): not semver, the tag
/// exists already, or not greater than [last] (R5).
String? validateNewVersion(
  String input, {
  required SemVer? last,
  required Set<String> existingTags,
  String? lastTag,
}) {
  final text = input.trim();
  final v = SemVer.tryParse(text);
  if (v == null) return 'Use X.Y.Z (ex.: 0.12.0).';
  final tag = tagFor(text, lastTag: lastTag);
  final bare = tag.replaceFirst(RegExp('^v'), '');
  if (existingTags.contains(tag) ||
      existingTags.contains(bare) ||
      existingTags.contains('v$bare')) {
    return 'A tag $tag já existe.';
  }
  if (last != null && !(v > last)) {
    return 'Precisa ser maior que a última versão ($last).';
  }
  return null;
}
