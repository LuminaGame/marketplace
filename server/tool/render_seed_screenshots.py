"""Renders the seed listings' screenshots from the real meshes in test-assets.

Run with Blender (headless, Cycles on the CPU — no GPU involved):

    blender --background --factory-startup --python tool/render_seed_screenshots.py

Writes server/seed/screenshots/<slug>.jpg. test-assets is only read.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'seed', 'screenshots')
ASSETS = os.path.join(os.environ.get('LUMINA_TEST_ASSETS') or os.path.join(HERE, '..', '..', 'test-assets'), 'Props')

LISTINGS = {
    'barrel': 'Barrels',
    'access-cards': 'Access_cards',
    'ac-units': 'AC_units',
    'banana-bunch': 'Banana Bunch',
    'chair': 'Chair',
    'jerry-can': 'JerryCan',
}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = 64
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = 'JPEG'
    scene.render.image_settings.quality = 88
    scene.view_settings.view_transform = 'AgX'
    world = bpy.data.worlds.new('World')
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes['Background']
    bg.inputs[0].default_value = (0.012, 0.012, 0.012, 1)
    bg.inputs[1].default_value = 1.0
    return scene


def import_row(folder):
    files = sorted(f for f in os.listdir(folder) if f.endswith('.glb'))
    x = 0.0
    for name in files:
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=os.path.join(folder, name))
        new = [o for o in bpy.data.objects if o not in before]
        meshes = [o for o in new if o.type == 'MESH']
        if not meshes:
            continue
        bpy.context.view_layer.update()
        corners = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
        lo = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
        hi = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
        width = hi.x - lo.x
        roots = [o for o in new if o.parent is None]
        offset = Vector((x - lo.x, -(lo.y + hi.y) / 2, -lo.z))
        for r in roots:
            r.location += offset
        x += width + max(0.15 * width, 0.05)
    bpy.context.view_layer.update()


def frame(scene):
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    corners = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
    lo = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
    hi = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
    center = (lo + hi) / 2
    size = max(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z)

    bpy.ops.mesh.primitive_plane_add(size=size * 20, location=(center.x, center.y, lo.z))
    ground = bpy.context.object
    mat = bpy.data.materials.new('Ground')
    mat.use_nodes = True
    mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (0.018, 0.018, 0.018, 1)
    mat.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value = 0.8
    ground.data.materials.append(mat)

    bpy.ops.object.light_add(type='SUN', rotation=(math.radians(50), math.radians(10), math.radians(35)))
    bpy.context.object.data.energy = 3.0
    bpy.ops.object.light_add(type='AREA', location=(center.x - size, center.y - size, lo.z + size * 1.5))
    fill = bpy.context.object
    fill.data.energy = 40 * size * size
    fill.data.size = size
    fill.data.color = (1.0, 0.85, 0.7)  # a warm fill
    fill.rotation_euler = (math.radians(60), 0, math.radians(-45))

    bpy.ops.object.camera_add()
    cam = bpy.context.object
    scene.camera = cam
    cam.data.lens = 50
    direction = Vector((0.0, -1.0, 0.45)).normalized()
    distance = size * 1.6 + 0.1
    cam.location = center + direction * distance
    cam.rotation_euler = (center - cam.location).to_track_quat('-Z', 'Y').to_euler()
    # Fit the row horizontally.
    cam.data.sensor_fit = 'HORIZONTAL'
    aspect = scene.render.resolution_x / scene.render.resolution_y
    fov_x = cam.data.angle_x
    fov_y = 2 * math.atan(math.tan(fov_x / 2) / aspect)
    radius_w = (hi.x - lo.x) / 2
    radius_h = max(hi.z - lo.z, hi.y - lo.y) / 2
    needed = max(radius_w / math.tan(fov_x / 2), radius_h / math.tan(fov_y / 2)) * 1.25 + size * 0.3
    cam.location = center + direction * needed


def main():
    os.makedirs(OUT, exist_ok=True)
    only = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    for slug, folder in LISTINGS.items():
        if only and slug not in only:
            continue
        scene = reset()
        import_row(os.path.join(ASSETS, folder))
        frame(scene)
        scene.render.filepath = os.path.join(OUT, slug + '.jpg')
        bpy.ops.render.render(write_still=True)
        print('rendered', scene.render.filepath)


main()
