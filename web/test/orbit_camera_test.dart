import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_marketplace_web/src/features/listing/model_viewer/orbit_camera.dart';
import 'package:vector_math/vector_math_64.dart';

/// A direction from the rotated frame to the world, the way Lumina's
/// `rotateVector` applies a component rotation (vector_math's
/// `Quaternion.rotated` applies the inverse).
Vector3 _rotate(Quaternion q, Vector3 v) => q.asRotationMatrix().transformed(v);

/// The 3D view's orbit camera (Lumina runtime axes: Y up, cm).
void main() {
  // A banana bunch: about 20 × 8 × 12 cm, resting on the ground.
  final min = Vector3(-10, 0, -6);
  final max = Vector3(10, 8, 6);
  final center = (min + max)..scale(0.5);
  final radius = (max - min).length / 2;

  test('framing puts the whole bounding sphere in view, looking at its centre', () {
    for (final aspect in [16 / 9, 1.0, 0.6]) {
      final camera = OrbitCamera()..frame(min, max, aspect: aspect);
      expect(camera.target, center);
      expect(camera.radius, closeTo(radius, 1e-9));
      final halfV = camera.fovDegrees * math.pi / 360;
      expect(camera.distance, greaterThanOrEqualTo(radius / math.sin(halfV) - 1e-9));
      expect(camera.containsSphere(center, radius, aspect: aspect), isTrue, reason: 'aspect $aspect');
      expect(camera.containsSphere(center, radius * 3, aspect: aspect), isFalse, reason: 'not framed far too loosely');
      // The camera looks at the target, from above the ground.
      final toTarget = (camera.target - camera.eye)..normalize();
      expect(camera.forward.dot(toTarget), closeTo(1, 1e-9));
      expect(camera.eye.y, greaterThan(center.y));
      // Its rotation maps −Z onto the view direction and keeps +Y up-ish.
      final q = camera.rotation;
      final f = _rotate(q, Vector3(0, 0, -1));
      expect(f.dot(toTarget), closeTo(1, 1e-6));
      expect(_rotate(q, Vector3(0, 1, 0)).y, greaterThan(0.9));
    }
  });

  test('orbit turns around the target and clamps pitch to ±85°', () {
    final camera = OrbitCamera()..frame(min, max);
    final distance = camera.distance;
    final yaw = camera.yaw;
    camera.orbit(100, 0);
    expect(camera.yaw, closeTo(yaw - 100 * OrbitCamera.orbitSpeed, 1e-12));
    expect((camera.eye - camera.target).length, closeTo(distance, 1e-9), reason: 'orbiting keeps the distance');
    camera.orbit(0, 100000);
    expect(camera.pitch, OrbitCamera.maxPitch);
    camera.orbit(0, -200000);
    expect(camera.pitch, -OrbitCamera.maxPitch);
    expect(_rotate(camera.rotation, Vector3(0, 1, 0)).length, closeTo(1, 1e-9), reason: 'no degenerate basis at the pole');
  });

  test('zoom scales the distance within the bounds-derived limits', () {
    final camera = OrbitCamera()..frame(min, max);
    final d = camera.distance;
    camera.zoom(-100);
    expect(camera.distance, lessThan(d));
    camera.zoom(200);
    expect(camera.distance, greaterThan(d));
    camera.zoom(-1e6);
    expect(camera.distance, camera.minDistance);
    expect(camera.minDistance, greaterThan(radius), reason: 'the camera never enters the model');
    camera.zoom(1e6);
    expect(camera.distance, camera.maxDistance);
  });

  test('pan moves the target in the view plane, within reach of the model', () {
    final camera = OrbitCamera()..frame(min, max);
    final before = camera.target.clone();
    final forward = camera.forward;
    camera.pan(40, -25, 720);
    final moved = camera.target - before;
    expect(moved.length, greaterThan(0));
    expect(moved.dot(forward), closeTo(0, 1e-9), reason: 'in the view plane');
    camera.pan(1e7, 0, 720);
    expect((camera.target - center).length, closeTo(camera.radius * 4, 1e-6), reason: 'clamped near the model');
  });

  test('reset returns to the framed pose', () {
    final camera = OrbitCamera()..frame(min, max);
    final eye = camera.eye;
    final revision = camera.revision;
    camera
      ..orbit(300, 120)
      ..zoom(500)
      ..pan(50, 50, 600);
    expect(camera.eye, isNot(eye));
    camera.reset();
    expect((camera.eye - eye).length, closeTo(0, 1e-9));
    expect(camera.target, center);
    expect(camera.revision, greaterThan(revision), reason: 'the scene re-syncs on every change');
  });
}
