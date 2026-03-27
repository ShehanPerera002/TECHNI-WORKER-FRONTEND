import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class MockPaymentScreen extends StatefulWidget {
  final bool isPaidDues; // true = paying dues, false = top-up
  final double? requiredAmount; // For dues: amount needed to clear

  const MockPaymentScreen({
    super.key,
    this.isPaidDues = false,
    this.requiredAmount,
  });

  @override
  State<MockPaymentScreen> createState() => _MockPaymentScreenState();
}

class _MockPaymentScreenState extends State<MockPaymentScreen> {
  static const String _baseUrl = 'https://techni-backend.onrender.com';

  final _cardNumberController = TextEditingController();
  final _cvvController = TextEditingController();
  final _amountController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill amount if it's dues payment
    if (widget.isPaidDues && widget.requiredAmount != null) {
      _amountController.text = widget.requiredAmount!.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _cardNumberController.dispose();
    _cvvController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _confirmPayment() async {
    if (_isLoading) return;

    // Validate inputs
    if (_cardNumberController.text.isEmpty || _cardNumberController.text.length < 16) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid card number (16 digits)')),
      );
      return;
    }

    if (_cvvController.text.isEmpty || _cvvController.text.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid CVV (3 digits)')),
      );
      return;
    }

    if (_amountController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an amount')),
      );
      return;
    }

    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount')),
      );
      return;
    }

    final workerId = FirebaseAuth.instance.currentUser?.uid;
    if (workerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not logged in. Please sign in again.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    // Simulate 2-second payment processing
    await Future.delayed(const Duration(seconds: 2));

    try {
      final endpoint = widget.isPaidDues ? '/api/worker/pay-dues' : '/api/worker/topup';
      final requestBody = {
        'workerId': workerId,
        'amount': amount,
      };
      print('[PAYMENT] Request to $endpoint: workerId=$workerId, amount=$amount');
      
      final response = await http.post(
        Uri.parse('$_baseUrl$endpoint'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );
      
      print('[PAYMENT] Response status: ${response.statusCode}, body: ${response.body}');

      if (!mounted) return;

      // Parse response body safely
      dynamic responseBody;
      try {
        responseBody = jsonDecode(response.body);
      } catch (e) {
        print('Failed to parse response: ${response.body}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Server error: Invalid response format'),
            backgroundColor: Colors.red,
          ),
        );
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.isPaidDues
                ? 'Dues paid successfully! Account unblocked.'
                : 'Wallet topped up successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        // Pop back — Firestore listener auto-updates the UI
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) Navigator.pop(context);
        });
      } else {
        final error = responseBody['error'] ?? responseBody['message'] ?? 'Unknown error';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment failed: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        print('Payment error: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final noticeColor = widget.isPaidDues ? Colors.red : Colors.blue;
    final buttonColor = widget.isPaidDues ? Colors.red.shade600 : const Color(0xFF2563EB);
    final title = widget.isPaidDues ? 'Pay Outstanding Dues' : 'Top Up Wallet';
    final buttonText = widget.isPaidDues ? 'Pay Dues' : 'Top Up';
    final noticeMessage = widget.isPaidDues
        ? 'Your account has outstanding platform dues. Pay now to resume accepting jobs.'
        : 'Add funds to your wallet to accept more jobs and maintain your account.';

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Notice (dues or top-up)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: noticeColor.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: noticeColor.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: noticeColor.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        noticeMessage,
                        style: TextStyle(color: noticeColor.shade800, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Card Number
              const Text(
                'Card Number',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _cardNumberController,
                keyboardType: TextInputType.number,
                maxLength: 16,
                decoration: InputDecoration(
                  hintText: '1234 5678 9012 3456',
                  counterText: '',
                  prefixIcon: const Icon(Icons.credit_card),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.black12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.black12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF2563EB)),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // CVV
              const Text(
                'CVV',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _cvvController,
                  keyboardType: TextInputType.number,
                  maxLength: 3,
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: '•••',
                    counterText: '',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.black12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.black12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF2563EB)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Amount field
              const Text(
                'Amount',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                enabled: !widget.isPaidDues, // Disabled for dues (pre-filled)
                decoration: InputDecoration(
                  hintText: 'Enter amount',
                  prefixIcon: const Icon(Icons.money),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.black12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.black12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF2563EB)),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.black12),
                  ),
                ),
              ),
              const SizedBox(height: 36),

              // Confirm Pay button
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: buttonColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  onPressed: _isLoading ? null : _confirmPayment,
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          buttonText,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 16),
              Center(
                child: Text(
                  'This is a mock payment. No real card will be charged.',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
