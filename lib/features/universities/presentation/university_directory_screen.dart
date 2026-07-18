import 'package:flutter/material.dart';

class UniversityDirectoryScreen extends StatelessWidget {
  const UniversityDirectoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Universities'),
        actions: [
          IconButton(icon: const Icon(Icons.filter_list), onPressed: () {}),
        ],
      ),
      body: ListView.builder(
        itemCount: 10,
        padding: const EdgeInsets.all(16.0),
        itemBuilder: (context, index) {
          return Card(
            margin: const EdgeInsets.only(bottom: 16.0),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              contentPadding: const EdgeInsets.all(16.0),
              leading: const CircleAvatar(
                radius: 30,
                child: Icon(Icons.account_balance, size: 30),
              ),
              title: Text('University ${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Eligibility, Fee Structure, Merit...'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () {},
            ),
          );
        },
      ),
    );
  }
}
