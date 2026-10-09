"""Secuencia de arranque de Daemon renderizada con Blender (headless).

Uso: /Applications/Blender.app/Contents/MacOS/Blender -b -P assets/vfx/render_boot.py
Escribe assets/vfx/boot/boot_0001.png … (RGBA, fondo transparente).
El lenguaje visual es el del Cubo de Neo: retícula alámbrica 3×3×3, ejes
verdes (col/row/phase), diagonales rojas y un recorrido blanco de 3 fases.
"""
import math
import os

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "boot")
FRAMES = 54
os.makedirs(OUT, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.frame_start, scene.frame_end = 1, FRAMES
scene.render.fps = 30
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "FLAT"
scene.display.shading.color_type = "OBJECT"
scene.display.render_aa = "16"
scene.render.film_transparent = True
scene.render.resolution_x = scene.render.resolution_y = 420
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.view_settings.view_transform = "Standard"

GRAY = (0.42, 0.42, 0.42, 1)
GREEN = (0.22, 1.0, 0.08, 1)
RED = (1.0, 0.18, 0.15, 1)
WHITE = (1, 1, 1, 1)
LILAC = (0.72, 0.6, 1.0, 1)

pivot = bpy.data.objects.new("pivot", None)
scene.collection.objects.link(pivot)


def segment(a, b, radius, color, start, length=6):
    a, b = Vector(a), Vector(b)
    direction = b - a
    bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=radius, depth=1, location=(0, 0, 0))
    obj = bpy.context.active_object
    obj.color = color
    # Origen en el extremo «a» para que crezca desde ahí.
    for v in obj.data.vertices:
        v.co.z += 0.5
    obj.location = a
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(direction.normalized())
    obj.parent = pivot
    obj.scale = (1, 1, 0.0001)
    obj.keyframe_insert("scale", frame=start)
    obj.scale = (1, 1, direction.length)
    obj.keyframe_insert("scale", frame=start + length)
    return obj


def dot(position, radius, color, start):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, radius=radius, location=position)
    obj = bpy.context.active_object
    obj.color = color
    obj.parent = pivot
    obj.scale = (0.0001,) * 3
    obj.keyframe_insert("scale", frame=start)
    obj.scale = (1.35,) * 3
    obj.keyframe_insert("scale", frame=start + 3)
    obj.scale = (1,) * 3
    obj.keyframe_insert("scale", frame=start + 6)
    return obj


E = 1.5
ticks = [-E, -E / 3, E / 3, E]
# Retícula: aparece desde el centro hacia fuera.
for i, a in enumerate(ticks):
    for j, b in enumerate(ticks):
        delay = int((abs(i - 1.5) + abs(j - 1.5)) * 3)
        segment((-E, a, b), (E, a, b), 0.006, GRAY, 1 + delay)
        segment((a, -E, b), (a, E, b), 0.006, GRAY, 3 + delay)
        segment((a, b, -E), (a, b, E), 0.006, GRAY, 5 + delay)
# Ejes verdes: columna (x), fila (y), fase (z).
segment((-E * 1.25, 0, 0), (E * 1.25, 0, 0), 0.016, GREEN, 20, 8)
segment((0, -E * 1.25, 0), (0, E * 1.25, 0), 0.016, GREEN, 22, 8)
segment((0, 0, -E * 1.25), (0, 0, E * 1.25), 0.016, GREEN, 24, 8)
# Diagonales rojas (como en el visor del Cubo).
segment((-E, E, -E), (E, -E, -E), 0.007, RED, 26, 7)
segment((-E, -E, -E), (E, E, -E), 0.007, RED, 27, 7)
segment((-E, E, E), (E, -E, -E), 0.006, RED, 28, 7)
# Recorrido de 3 fases: fase 1 → 2 → 3.
points = [(-E / 1.5, E / 1.5, -E / 1.5), (0, E / 3, 0), (E / 1.5, -E / 3, E / 1.5)]
for k, p in enumerate(points):
    dot(p, 0.075, WHITE if k < 2 else LILAC, 32 + k * 5)
segment(points[0], points[1], 0.02, WHITE, 34, 5)
segment(points[1], points[2], 0.02, WHITE, 39, 5)

# Órbita suave del conjunto.
pivot.rotation_euler = (math.radians(18), 0, math.radians(-30))
pivot.keyframe_insert("rotation_euler", frame=1)
pivot.rotation_euler = (math.radians(24), 0, math.radians(32))
pivot.keyframe_insert("rotation_euler", frame=FRAMES)

camera_data = bpy.data.cameras.new("camera")
camera_data.type = "PERSP"
camera_data.lens = 50
camera = bpy.data.objects.new("camera", camera_data)
scene.collection.objects.link(camera)
camera.location = (0, -9.5, 2.2)
camera.rotation_euler = (math.radians(78), 0, 0)
scene.camera = camera

scene.render.filepath = os.path.join(OUT, "boot_")
bpy.ops.render.render(animation=True)
print("RENDER OK", OUT)
# Tras el render: `python3 assets/vfx/quantize.py` reduce los PNG a paleta (≈10× menos peso).
