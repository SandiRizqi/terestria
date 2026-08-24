"""Buat fixture .osm.pbf kecil dgn writer yang SAMA dgn roads_osm_builder.write_pbf.
Node/way/tag diketahui → dipakai menguji pbf_reader.dart (Dart).
Jalankan: python generate_fixture.py
"""
import os, osmium
from osmium.osm.mutable import Node, Way

OUT = os.path.join(os.path.dirname(__file__), 'tiny_roads.osm.pbf')
# node id -> (lon, lat)  (osmium Location = lon,lat)
NODES = {1: (100.0000, 1.0000), 2: (100.0010, 1.0010),
         3: (100.0020, 1.0000), 4: (100.0030, 1.0010)}
WAYS = [
    (10, [1, 2, 3], {'highway': 'residential', 'name': 'Jl Test',
                     'maxspeed': '40', 'oneway': 'no'}),
    (11, [2, 4],    {'highway': 'secondary', 'name': 'Jl Dua'}),
]

if os.path.exists(OUT):
    os.remove(OUT)
w = osmium.SimpleWriter(OUT)
try:
    for nid, (lon, lat) in NODES.items():
        w.add_node(Node(id=nid, location=(lon, lat), tags={}))
    for wid, refs, tags in WAYS:
        w.add_way(Way(id=wid, nodes=refs, tags=tags))
finally:
    w.close()
print('wrote', OUT, os.path.getsize(OUT), 'bytes')
