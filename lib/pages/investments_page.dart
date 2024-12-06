import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class InvestmentsPage extends StatelessWidget {
  const InvestmentsPage({Key? key}) : super(key: key);

  Future<void> _handleInvestment(BuildContext context, String investmentType, double amount) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw 'User not authenticated';

      // Start a Firebase transaction to ensure data consistency
      await FirebaseFirestore.instance.runTransaction<void>((transaction) async {
        // Get user's current data
        final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
        final userDoc = await transaction.get(userRef);
        
        if (!userDoc.exists) throw 'User document not found';
        
        final currentBalance = (userDoc.data()?['balance'] ?? 0.0).toDouble();
        final currentInvestments = (userDoc.data()?['totalInvested'] ?? 0.0).toDouble();
        
        // Validate balance
        if (currentBalance < amount) {
          throw 'Insufficient balance';
        }

        // Create new document references
        final investmentRef = FirebaseFirestore.instance.collection('investments').doc();
        final transactionRef = userRef.collection('transactions').doc();

        // Update user data
        transaction.update(userRef, {
          'balance': currentBalance - amount,
          'totalInvested': currentInvestments + amount,
        });

        // Create investment record
        transaction.set(investmentRef, {
          'userId': user.uid,
          'type': investmentType,
          'amount': amount,
          'status': 'active',
          'returnRate': _getReturnRate(investmentType),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'expectedReturn': amount * _getReturnRate(investmentType),
        });

        // Create transaction record
        transaction.set(transactionRef, {
          'type': 'Investment',
          'subtype': investmentType,
          'amount': -amount,
          'timestamp': FieldValue.serverTimestamp(),
          'status': 'completed',
          'description': 'Investment in $investmentType',
          'balanceAfter': currentBalance - amount,
          'category': 'investment',
        });
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully invested Rp${amount.toStringAsFixed(0)} in $investmentType'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Investment failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  double _getReturnRate(String investmentType) {
    switch (investmentType) {
      case 'Stocks':
        return 0.15; // 15% p.a.
      case 'Mutual Funds':
        return 0.12; // 12% p.a.
      case 'Bonds':
        return 0.07; // 7% p.a.
      default:
        return 0.10; // 10% p.a.
    }
  }

  Widget _buildInvestmentStats() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser?.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final userData = snapshot.data?.data() as Map<String, dynamic>?;
        final totalInvested = userData?['totalInvested'] ?? 0.0;
        final totalReturns = userData?['investmentReturns'] ?? 0.0;

        return Container(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              const Text(
                'Investment Portfolio',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatCard(
                    'Total Invested',
                    'Rp${totalInvested.toStringAsFixed(0)}',
                    Icons.account_balance_wallet
                  ),
                  _buildStatCard(
                    'Total Returns',
                    'Rp${totalReturns.toStringAsFixed(0)}',
                    Icons.trending_up
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Icon(icon, size: 32, color: Colors.blue),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontSize: 14)),
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Investments'),
        backgroundColor: Colors.blue,
      ),
      body: RefreshIndicator(
        onRefresh: () async => await Future.delayed(const Duration(seconds: 1)),
        child: ListView(
          children: [
            _buildInvestmentStats(),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Investment Options',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  InvestmentCard(
                    title: 'Stocks',
                    description: 'Invest in company shares\nMin. investment: \$100',
                    icon: Icons.trending_up,
                    returnRate: '12-15% p.a.',
                    onInvest: (amount) => _handleInvestment(context, 'Stocks', amount),
                  ),
                  InvestmentCard(
                    title: 'Mutual Funds',
                    description: 'Professionally managed investment funds\nMin. investment: \$100',
                    icon: Icons.account_balance,
                    returnRate: '8-12% p.a.',
                    onInvest: (amount) => _handleInvestment(context, 'Mutual Funds', amount),
                  ),
                  InvestmentCard(
                    title: 'Bonds',
                    description: 'Government and corporate bonds\nMin. investment: \$100',
                    icon: Icons.security,
                    returnRate: '5-7% p.a.',
                    onInvest: (amount) => _handleInvestment(context, 'Bonds', amount),
                  ),
                ],
              ),
            ),
            _buildInvestmentHistory(),
          ],
        ),
      ),
    );
  }

  Widget _buildInvestmentHistory() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      child: StreamBuilder<QuerySnapshot>(
        stream: _getInvestmentHistory(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Something went wrong'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text('No investment history available'),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Recent Investments',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ...snapshot.data!.docs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8.0),
                  child: ListTile(
                    leading: Icon(_getInvestmentIcon(data['type'])),
                    title: Text(data['type']),
                    subtitle: Text('Amount: \$${data['amount']}'),
                    trailing: Text(
                      _formatDate(data['timestamp']?.toDate()),
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                );
              }).toList(),
            ],
          );
        },
      ),
    );
  }

  Stream<QuerySnapshot> _getInvestmentHistory() {
    return FirebaseFirestore.instance
        .collection('investments')
        .where('userId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
        .orderBy('createdAt', descending: true)
        .limit(5)
        .snapshots();
  }

  IconData _getInvestmentIcon(String type) {
    switch (type) {
      case 'Stocks':
        return Icons.trending_up;
      case 'Mutual Funds':
        return Icons.account_balance;
      case 'Bonds':
        return Icons.security;
      default:
        return Icons.attach_money;
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    return '${date.day}/${date.month}/${date.year}';
  }

  double _calculateReturns(double amount, String investmentType, DateTime startDate) {
    final daysPassed = DateTime.now().difference(startDate).inDays;
    final annualRate = _getReturnRate(investmentType);
    return amount * (annualRate / 365 * daysPassed);
  }
}

mixin InvestmentValidationMixin {
  String? validateAmount(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter an amount';
    }
    
    final amount = double.tryParse(value.replaceAll(',', ''));
    if (amount == null || amount <= 0) {
      return 'Please enter a valid amount';
    }
    
    if (amount < 100000) {
      return 'Minimum investment is Rp100,000';
    }
    
    if (amount > 1000000000) {
      return 'Maximum investment is Rp1,000,000,000';
    }
    
    return null;
  }
}

class InvestmentCard extends StatelessWidget with InvestmentValidationMixin {
  final String title;
  final String description;
  final IconData icon;
  final String returnRate;
  final Function(double) onInvest;

  const InvestmentCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.returnRate,
    required this.onInvest,
    Key? key,
  }) : super(key: key);

  void _showInvestmentDialog(BuildContext context) {
    final formKey = GlobalKey<FormState>();
    final amountController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Invest in $title'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Amount (Rp)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.attach_money),
                ),
                validator: validateAmount,
              ),
              const SizedBox(height: 8),
              Text(
                'Expected Returns: $returnRate',
                style: const TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                final amount = double.parse(
                  amountController.text.replaceAll(',', '')
                );
                onInvest(amount);
                Navigator.pop(context);
              }
            },
            child: const Text('Invest'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16.0),
      child: InkWell(
        onTap: () => _showInvestmentDialog(context),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 32, color: Colors.blue),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(description),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Expected Returns: $returnRate',
                style: const TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}