import 'package:flutter/material.dart';

class ResponseContainer extends StatelessWidget {
  final String response;
  final bool isError;
  final ScrollController _scrollController = ScrollController();

  ResponseContainer({
    super.key,
    required this.response,
    this.isError = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 200,
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isError ? Colors.red : Colors.green,
          width: 2,
        ),
      ),
      child: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isError ? 'Erro' : 'Resposta',
                  style: TextStyle(
                    color: isError ? Colors.red : Colors.green,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  DateTime.now().toString().substring(0, 19),
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(color: Colors.grey),
            const SizedBox(height: 8),
            SelectableText(
              response.isEmpty ? 'Nenhuma resposta ainda.' : response,
              style: TextStyle(
                color: isError ? Colors.red.shade300 : Colors.white,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
