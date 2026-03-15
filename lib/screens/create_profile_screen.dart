import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart'; // Added for date formatting
import '../widgets/app_header.dart';
import '../widgets/input_field.dart';
import '../widgets/primary_button.dart';
import 'select_category_screen.dart';

class CreateProfileScreen extends StatefulWidget {
  const CreateProfileScreen({super.key});

  @override
  State<CreateProfileScreen> createState() => _CreateProfileScreenState();
}

class _CreateProfileScreenState extends State<CreateProfileScreen> {
  // Text controllers for input fields
  final nameCtrl = TextEditingController();
  final nicCtrl = TextEditingController();

  // Variables for date of birth and language
  DateTime? selectedBirthDate;
  String selectedLanguage = "English"; 
  final List<String> languages = ["English", "Sinhala", "Tamil"];

  // Variables to hold selected files in memory
  PlatformFile? _profilePhoto;
  PlatformFile? _nicFrontFile;
  PlatformFile? _nicBackFile;
  PlatformFile? _policeCertFile;

  @override
  void dispose() {
    nameCtrl.dispose();
    nicCtrl.dispose();
    super.dispose();
  }

  // Function to show the Date Picker
  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000),
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != selectedBirthDate) {
      setState(() {
        selectedBirthDate = picked;
      });
    }
  }

  // Function to pick files using FilePicker
  Future<void> _pickFile(String type) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
        withData: true, // Crucial: Loads bytes into memory
      );

      if (result != null && result.files.single.bytes != null) {
        setState(() {
          if (type == 'front') _nicFrontFile = result.files.first;
          if (type == 'back') _nicBackFile = result.files.first;
          if (type == 'police') _policeCertFile = result.files.first;
          if (type == 'profile') _profilePhoto = result.files.first;
        });
      }
    } catch (e) {
      if (!mounted) return;
      _showError('Error picking file: $e');
    }
  }

  // Validates if all fields are filled before proceeding
  bool _validateFields() {
    if (nameCtrl.text.trim().isEmpty) {
      _showError('Please enter your full name');
      return false;
    }
    if (selectedBirthDate == null) {
      _showError('Please select your date of birth');
      return false;
    }
    if (nicCtrl.text.trim().isEmpty) {
      _showError('Please enter your NIC number');
      return false;
    }
    if (_profilePhoto == null) {
      _showError('Please upload a profile photo');
      return false;
    }
    if (_nicFrontFile == null || _nicBackFile == null || _policeCertFile == null) {
      _showError('All identification documents are required');
      return false;
    }
    return true;
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
    );
  }

  // Handles navigation to the next screen with all data
  void _handleNext() {
    if (!_validateFields()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.phoneNumber == null) {
      _showError('Session expired. Please sign in again.');
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SelectCategoryScreen(
          name: nameCtrl.text.trim(),
          birthDate: DateFormat('yyyy-MM-dd').format(selectedBirthDate!),
          phone: user.phoneNumber!,
          language: selectedLanguage,
          profilePhoto: _profilePhoto!,
          nicFront: _nicFrontFile!,
          nicBack: _nicBackFile!,
          policeReport: _policeCertFile!,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppHeader(title: "Create Your Profile"),
              const SizedBox(height: 25),
              
              // Profile Image Picker UI
              Center(
                child: GestureDetector(
                  onTap: () => _pickFile('profile'),
                  child: Column(
                    children: [
                      Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          CircleAvatar(
                            radius: 50,
                            backgroundColor: const Color(0xFFF0F4FF),
                            backgroundImage: _profilePhoto != null 
                                ? MemoryImage(_profilePhoto!.bytes!) 
                                : null,
                            child: _profilePhoto == null
                                ? const Icon(Icons.person, size: 50, color: Color(0xFF2563EB))
                                : null,
                          ),
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Color(0xFF2563EB),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text("Upload Photo", style: TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),
              InputField(label: "Full Name", controller: nameCtrl),
              const SizedBox(height: 15),
              
              // Date of Birth Selector
              const Text("Date of Birth", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => _selectDate(context),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        selectedBirthDate == null 
                            ? "Select Date" 
                            : DateFormat('yyyy-MM-dd').format(selectedBirthDate!),
                        style: TextStyle(color: selectedBirthDate == null ? Colors.black54 : Colors.black87),
                      ),
                      const Icon(Icons.calendar_month, color: Color(0xFF2563EB)),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 15),

              // Language Selection Dropdown
              const Text("Preferred Language", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedLanguage,
                    isExpanded: true,
                    items: languages.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                    onChanged: (val) => setState(() => selectedLanguage = val!),
                  ),
                ),
              ),

              const SizedBox(height: 15),
              InputField(label: "NIC Number", controller: nicCtrl),
              
              const SizedBox(height: 20),
              const Text("Required Documents", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              
              // Custom Widget-like calls for document upload boxes
              _uploadBox("NIC Front Photo", _nicFrontFile, () => _pickFile('front')),
              const SizedBox(height: 10),
              _uploadBox("NIC Back Photo", _nicBackFile, () => _pickFile('back')),
              const SizedBox(height: 10),
              _uploadBox("Police Report", _policeCertFile, () => _pickFile('police')),
              
              const SizedBox(height: 30),
              PrimaryButton(text: "Next Step", onPressed: _handleNext),
            ],
          ),
        ),
      ),
    );
  }

  // Reusable widget for document upload rows
  Widget _uploadBox(String label, PlatformFile? file, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: file != null ? const Color(0xFFF0F7FF) : Colors.white,
          border: Border.all(color: file != null ? const Color(0xFF2563EB) : Colors.black12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(file != null ? Icons.check_circle : Icons.upload_file, color: const Color(0xFF2563EB)),
            const SizedBox(width: 10),
            Expanded(child: Text(file != null ? file.name : label, overflow: TextOverflow.ellipsis)),
            Text(file != null ? "Change" : "Upload", style: const TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}