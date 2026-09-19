import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../services/api_service.dart';
import '../services/avatar_service.dart';
import 'avatar_picker_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String username;
  const ProfileScreen({super.key, required this.username});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? profileData;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    try {
      final data = await ApiService.getProfile(widget.username);
      if (mounted) {
        setState(() {
          profileData = data;
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  String _cleanValue(dynamic value, {String fallback = "Not available"}) {
    if (value == null) return fallback;
    final s = value.toString().trim();
    return s.isEmpty ? fallback : s;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        title: const Text("Student Profile", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary(context),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : profileData == null || profileData!.isEmpty
              ? Center(child: Text("Profile data not available", style: TextStyle(color: AppColors.textSecondary(context))))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  physics: const BouncingScrollPhysics(),
                  children: [
                    // Avatar and Name
                    Center(
                      child: Column(
                        children: [
                          GestureDetector(
                            onTap: () => AvatarPickerSheet.show(
                              context,
                              username: widget.username,
                              name: profileData?["name"] ?? widget.username,
                            ),
                            child: Stack(
                              children: [
                                ValueListenableBuilder<String?>(
                                  valueListenable: AvatarService.instance.avatarNotifier,
                                  builder: (context, choice, _) {
                                    return AvatarService.buildAvatar(
                                      choice: choice,
                                      name: profileData?["name"] ?? widget.username,
                                      size: 100,
                                    );
                                  },
                                ),
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: AppColors.scaffoldBg(context), width: 2),
                                    ),
                                    child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _cleanValue(profileData!["name"], fallback: widget.username),
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary(context),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              widget.username,
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Personal Info
                    _sectionHeader(context, "Personal Information"),
                    const SizedBox(height: 12),
                    _detailsCard(context, [
                      _buildProfileRow(context, Icons.email_outlined, "Email", _cleanValue(profileData!["email"])),
                      _buildProfileRow(context, Icons.cake_outlined, "Date of Birth", _cleanValue(profileData!["dob"])),
                      _buildProfileRow(context, Icons.wc_outlined, "Gender", _cleanValue(profileData!["gender"])),
                      _buildProfileRow(context, Icons.bloodtype_outlined, "Blood Group", _cleanValue(profileData!["blood_group"])),
                    ]),
                    const SizedBox(height: 24),

                    // Academic Info
                    _sectionHeader(context, "Academic Information"),
                    const SizedBox(height: 12),
                    _detailsCard(context, [
                      _buildProfileRow(context, Icons.school_outlined, "Program", _cleanValue(profileData!["program"])),
                      _buildProfileRow(context, Icons.account_tree_outlined, "Branch", _cleanValue(profileData!["branch"])),
                      _buildProfileRow(context, Icons.apartment_outlined, "School", _cleanValue(profileData!["school"])),
                    ]),
                    const SizedBox(height: 24),

                    // Mentor/Proctor Details
                    _sectionHeader(context, "Proctor Information"),
                    const SizedBox(height: 12),
                    Builder(builder: (context) {
                      final mentor = profileData!["mentor_details"] as Map<String, dynamic>? ?? {};
                      String facultyName = _cleanValue(mentor["faculty_name"] ?? profileData!["mentor"], fallback: "");
                      final studentName = _cleanValue(profileData!["name"], fallback: "").toUpperCase();
                      final studentEmail = _cleanValue(profileData!["email"], fallback: "").toLowerCase();

                      // Guard against student details leaking into proctor fields
                      if (facultyName.toUpperCase() == studentName || facultyName.toUpperCase() == widget.username.toUpperCase()) {
                        facultyName = "";
                      }
                      String mentorEmail = _cleanValue(mentor["faculty_email"], fallback: "");
                      if (mentorEmail.toLowerCase() == studentEmail) {
                        mentorEmail = "";
                      }
                      final mentorMobile = _cleanValue(mentor["faculty_mobile"] ?? mentor["faculty_mobile_number"], fallback: "");
                      final facultyDesignation = _cleanValue(mentor["faculty_designation"], fallback: "");
                      final facultyDepartment = _cleanValue(mentor["faculty_department"], fallback: "");
                      final facultySchool = _cleanValue(mentor["school"], fallback: "");
                      final facultyCabin = _cleanValue(mentor["cabin"], fallback: "");
                      final facultyIntercom = _cleanValue(mentor["faculty_intercom"], fallback: "");

                      return _detailsCard(context, [
                        _buildProfileRow(context, Icons.person_outline, "Faculty Name", facultyName.isEmpty ? "Not available" : facultyName),
                        if (facultyDesignation.isNotEmpty)
                          _buildProfileRow(context, Icons.badge_outlined, "Designation", facultyDesignation),
                        if (facultyDepartment.isNotEmpty)
                          _buildProfileRow(context, Icons.business_outlined, "Department", facultyDepartment),
                        if (facultySchool.isNotEmpty)
                          _buildProfileRow(context, Icons.school_outlined, "School", facultySchool),
                        if (facultyCabin.isNotEmpty)
                          _buildProfileRow(context, Icons.meeting_room_outlined, "Cabin", facultyCabin),
                        if (mentorEmail.isNotEmpty)
                          _buildProfileRow(context, Icons.email_outlined, "Email", mentorEmail),
                        if (facultyIntercom.isNotEmpty)
                          _buildProfileRow(context, Icons.phone_outlined, "Intercom", facultyIntercom),
                        if (mentorMobile.isNotEmpty)
                          _buildProfileRow(context, Icons.phone_android_outlined, "Mobile", mentorMobile),
                      ]);
                    }),
                    const SizedBox(height: 32),
                  ],
                ),
    );
  }

  Widget _buildProfileRow(BuildContext context, IconData icon, String label, String value) {
    final displayValue = value.trim().isEmpty ? "Not available" : value.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.textMuted(context)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: AppColors.textMuted(context))),
                const SizedBox(height: 2),
                Text(
                  displayValue,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary(context)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary(context),
      ),
    );
  }

  Widget _detailsCard(BuildContext context, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: children,
      ),
    );
  }
}
