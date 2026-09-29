import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

/// The 3D view's orbit camera, in Lumina runtime axes: Y up, −Z forward,
/// centimetres (glTF metres × 100).
///
/// The camera circles [target] at [distance], [yaw] around +Y (0 looks down
/// −Z from the +Z side) and [pitch] above the ground plane. [frame] fits a
/// model's bounds; [reset] returns to that framed pose. Pure math: the
/// Lumina scene copies [eye] / [rotation] into its camera component.
class OrbitCamera {
  OrbitCamera({this.fovDegrees = 40});

  /// Vertical field of view.
  final double fovDegrees;

  /// The pose [frame] computes and [reset] returns to.
  static const double defaultYaw = 35 * math.pi / 180;
  static const double defaultPitch = 18 * math.pi / 180;

  /// Pitch stays within ±85° so the camera never flips over the pole.
  static const double maxPitch = 85 * math.pi / 180;

  /// Radians per pixel of drag.
  static const double orbitSpeed = 0.008;

  final Vector3 target = Vector3.zero();
  double yaw = defaultYaw;
  double pitch = defaultPitch;
  double distance = 300;

  /// Bounding-sphere radius of the framed model (cm).
  double radius = 100;

  /// Distance limits derived from [radius] by [frame].
  double minDistance = 10;
  double maxDistance = 10000;

  final Vector3 _framedTarget = Vector3.zero();
  double _framedDistance = 300;

  /// Bumped on every change, so a scene can tell when to re-sync.
  int revision = 0;

  double get _halfFov => fovDegrees * math.pi / 360;

  /// Fits a model whose bounds run from [min] to [max] (cm): the target is the
  /// bounds' centre and the whole bounding sphere is in view at [aspect]
  /// (width / height), with a margin.
  void frame(Vector3 min, Vector3 max, {double aspect = 16 / 9}) {
    final center = (min + max)..scale(0.5);
    final r = math.max((max - min).length / 2, 0.5);
    // The narrower of the two half-angles decides.
    final halfV = _halfFov;
    final halfH = math.atan(math.tan(halfV) * aspect);
    final half = math.min(halfV, halfH);
    radius = r;
    _framedTarget.setFrom(center);
    _framedDistance = r / math.sin(half) * 1.08;
    minDistance = r * 1.05;
    maxDistance = _framedDistance * 8;
    reset();
  }

  /// Back to the framed pose.
  void reset() {
    target.setFrom(_framedTarget);
    distance = _framedDistance;
    yaw = defaultYaw;
    pitch = defaultPitch;
    revision++;
  }

  /// Drags of [dx], [dy] pixels: right turns the camera left around the
  /// model (the model seems to follow the mouse), down raises it.
  void orbit(double dx, double dy) {
    yaw -= dx * orbitSpeed;
    pitch = (pitch + dy * orbitSpeed).clamp(-maxPitch, maxPitch);
    revision++;
  }

  /// A wheel of [scrollDelta] (positive = away, as browsers report scrolling
  /// down): the distance scales exponentially, within the limits.
  void zoom(double scrollDelta) {
    distance = (distance * math.exp(scrollDelta * 0.0015)).clamp(minDistance, maxDistance);
    revision++;
  }

  /// Moves the target in the view plane so a point under the cursor follows a
  /// drag of [dx], [dy] pixels on a viewport [viewportHeight] pixels tall.
  void pan(double dx, double dy, double viewportHeight) {
    final worldPerPixel = 2 * distance * math.tan(_halfFov) / math.max(viewportHeight, 1);
    final (right, up, _) = _basis();
    target
      ..addScaled(right, -dx * worldPerPixel)
      ..addScaled(up, dy * worldPerPixel);
    // Keep the model within reach.
    final offset = target - _framedTarget;
    final limit = radius * 4;
    if (offset.length > limit) target.setFrom(_framedTarget + (offset..scale(limit / offset.length)));
    revision++;
  }

  /// Unit vector from [target] to the eye.
  Vector3 get _toEye => Vector3(math.cos(pitch) * math.sin(yaw), math.sin(pitch), math.cos(pitch) * math.cos(yaw));

  /// Camera position.
  Vector3 get eye => target + (_toEye..scale(distance));

  /// Camera right, up and back (+Z) axes.
  (Vector3, Vector3, Vector3) _basis() {
    final back = _toEye;
    final right = Vector3(0, 1, 0).cross(back)..normalize();
    final up = back.cross(right)..normalize();
    return (right, up, back);
  }

  /// The camera's rotation: its −Z looks at [target], +Y is up.
  Quaternion get rotation {
    final (right, up, back) = _basis();
    return Quaternion.fromRotation(Matrix3.columns(right, up, back))..normalize();
  }

  /// Where the camera looks (−Z of [rotation]).
  Vector3 get forward => _toEye..scale(-1);

  /// Near / far clip planes that suit the current distance.
  double get nearClip => math.max(0.5, (distance - radius * 1.5) * 0.25).clamp(0.5, 100).toDouble();
  double get farClip => distance * 4 + radius * 400;

  /// Whether a sphere at [center] with [r] is fully inside the view frustum
  /// at [aspect] (a check for tests and the framing contract).
  bool containsSphere(Vector3 center, double r, {double aspect = 16 / 9}) {
    final (right, up, back) = _basis();
    final rel = center - eye;
    final z = -rel.dot(back);
    if (z - r < 0) return false;
    final tanV = math.tan(_halfFov);
    final tanH = tanV * aspect;
    // Distance from the sphere centre to each side plane.
    bool inside(double coord, double tanHalf) {
      final cos = 1 / math.sqrt(1 + tanHalf * tanHalf);
      return (tanHalf * z - coord.abs()) * cos >= r;
    }

    return inside(rel.dot(right), tanH) && inside(rel.dot(up), tanV);
  }
}
