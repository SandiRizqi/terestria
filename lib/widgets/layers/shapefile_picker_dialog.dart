import 'package:flutter/material.dart';

/// Dialog memilih satu shapefile dari zip yang berisi beberapa. [names] =
/// path tanpa `.shp` (bisa di dalam folder). Mengembalikan nama terpilih atau
/// null bila dibatalkan.
Future<String?> showShapefilePicker(BuildContext context, List<String> names) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Pilih shapefile'),
      contentPadding: const EdgeInsets.only(top: 12, bottom: 8),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text('Zip berisi beberapa shapefile. Impor yang mana?'),
            ),
            for (final name in names)
              ListTile(
                leading: const Icon(Icons.layers_outlined),
                title: Text(name.split('/').last),
                subtitle: name.contains('/')
                    ? Text(name.substring(0, name.lastIndexOf('/')),
                        maxLines: 1, overflow: TextOverflow.ellipsis)
                    : null,
                onTap: () => Navigator.pop(ctx, name),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Batal'),
        ),
      ],
    ),
  );
}
