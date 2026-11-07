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
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        title: Text(
          "Student Profile",
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: AppColors.textPrimary(context),
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : profileData == null || profileData!.isEmpty
              ? Center(child: Text("Profile data not available", style: TextStyle(color: AppColors.textSecondary(context))))
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                                      size: 96,
                                    );
                                  },
                                ),
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(7),
                                    decoration: BoxDecoration(
                                      color: primaryColor,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: AppColors.scaffoldBg(context), width: 2.5),
                                    ),
                                    child: const Icon(Icons.camera_alt_rounded, size: 14, color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            _cleanValue(profileData!["name"], fallback: widget.username),
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.4,
                              color: AppColors.textPrimary(context),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: primaryColor.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: primaryColor.withValues(alpha: 0.15)),
                            ),
                            child: Text(
                              widget.username,
                              style: TextStyle(
                                color: primaryColor,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Personal Info
                    _sectionHeader(context, "Personal Information"),
                    const SizedBox(height: 10),
                    _detailsCard(context, [
                      _buildProfileRow(context, Icons.email_outlined, "Email", _cleanValue(profileData!["email"])),
                      _buildProfileRow(context, Icons.cake_outlined, "Date of Birth", _cleanValue(profileData!["dob"])),
                      _buildProfileRow(context, Icons.wc_outlined, "Gender", _cleanValue(profileData!["gender"])),
                      _buildProfileRow(context, Icons.bloodtype_outlined, "Blood Group", _cleanValue(profileData!["blood_group"])),
                    ]),
                    const SizedBox(height: 22),

                    // Academic Info
                    _sectionHeader(context, "Academic Information"),
                    const SizedBox(height: 10),
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
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: primaryColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 11, color: AppColors.textMuted(context))),
                const SizedBox(height: 1),
                Text(
                  displayValue,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary(context)),
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
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: AppColors.textSecondary(context),
      ),
    );
  }

  Widget _detailsCard(BuildContext context, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: AppColors.isDark(context) ? 0.2 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Column(
        children: children,
      ),
    );
  }
}
