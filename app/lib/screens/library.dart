import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../services/api.dart';
import '../widgets/common.dart';
import 'post_detail.dart';

class LibraryScreen extends StatelessWidget {
  final String workspaceId;
  final Brand brand;
  const LibraryScreen({super.key, required this.workspaceId, required this.brand});

  @override
  Widget build(BuildContext context) {
    final api = Api.instance;
    return StreamBuilder<List<Post>>(
      stream: api.posts(workspaceId, brand.id),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final posts = snap.data!;
        if (posts.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('No posts yet. Create your first one from the Create tab.', textAlign: TextAlign.center),
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 260, mainAxisSpacing: 12, crossAxisSpacing: 12),
          itemCount: posts.length,
          itemBuilder: (context, i) {
            final p = posts[i];
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PostDetailScreen(workspaceId: workspaceId, brand: brand, postId: p.id),
              )),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(fit: StackFit.expand, children: [
                  if (p.status == 'ready')
                    StorageImage(key: ValueKey(p.imagePath), path: p.imagePath, resolve: api.downloadUrl)
                  else
                    ColoredBox(
                      color: Colors.black12,
                      child: Center(
                        child: p.status == 'failed' ? const Icon(Icons.error_outline) : const CircularProgressIndicator(),
                      ),
                    ),
                  Positioned(
                    left: 8,
                    top: 8,
                    child: CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.white,
                      child: Icon(Platform.values.byName(p.platform).icon, size: 16, color: Colors.black87),
                    ),
                  ),
                ]),
              ),
            );
          },
        );
      },
    );
  }
}
