import 'package:flutter/material.dart';

class TestPracticeScreen extends StatefulWidget {
  final String testId;
  const TestPracticeScreen({super.key, required this.testId});

  @override
  State<TestPracticeScreen> createState() => _TestPracticeScreenState();
}

class _TestPracticeScreenState extends State<TestPracticeScreen> {
  int _currentQuestion = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Practice Test'),
        actions: [
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                '45:00',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.redAccent),
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Question ${_currentQuestion + 1} of 50', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            const Text(
              'What is the powerhouse of the cell?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 32),
            ...['Nucleus', 'Mitochondria', 'Ribosome', 'Golgi Apparatus'].map((option) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.all(16.0),
                    alignment: Alignment.centerLeft,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(option, style: const TextStyle(fontSize: 16)),
                ),
              );
            }),
          ],
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: _currentQuestion > 0 ? () => setState(() => _currentQuestion--) : null,
              child: const Text('Previous'),
            ),
            ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text('End Test', style: TextStyle(color: Colors.white)),
            ),
            TextButton(
              onPressed: () => setState(() => _currentQuestion++),
              child: const Text('Next'),
            ),
          ],
        ),
      ),
    );
  }
}
