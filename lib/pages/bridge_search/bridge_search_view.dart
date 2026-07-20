import 'package:fluffychat/widgets/avatar.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'bridge_search.dart';

class BridgeSearchView extends StatelessWidget {
  final BridgeSearchController controller;

  const BridgeSearchView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: context.pop),
        title: const Text('Search contacts'),
      ),
      body: controller.loading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: controller.searchController,
                    onChanged: controller.onQueryChanged,
                    autofocus: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_outlined),
                      hintText: 'Search by name, phone number...',
                    ),
                  ),
                ),
                if (controller.bridgeErrors.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: controller.bridgeErrors.entries
                          .map(
                            (e) => Text(
                              '${e.key}: ${e.value}',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                                fontSize: 12,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    itemCount: controller.results.length,
                    itemBuilder: (context, i) {
                      final result = controller.results[i];
                      return ListTile(
                        leading: Avatar(
                          mxContent: null,
                          name: result.contact.name,
                        ),
                        title: Text(result.contact.name),
                        subtitle: Text(result.bridge.label),
                        onTap: () => controller.startChat(result),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
