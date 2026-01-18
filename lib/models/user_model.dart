class AiaUser {
  final String id; // Firestore ID or Username
  final String name;
  final String role; // "Master" or "Editor"
  final String company; // Stores Company Name or ID
  final String email;
  final String password; // Stored plainly as requested for simple internal tool
  final String fullName;
  final bool isBlocked;
  final int albumsPerHourGoal; // For Master
  final int photosPerHourGoal; // For Editor

  AiaUser({
    required this.id,
    required this.name,
    this.role = "Editor",
    this.company = "Default",
    this.email = "",
    this.password = "",
    this.fullName = "",
    this.isBlocked = false,
    this.albumsPerHourGoal = 5,
    this.photosPerHourGoal = 100,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'role': role,
      'company': company,
      'email': email,
      'password': password,
      'fullName': fullName,
      'isBlocked': isBlocked,
      'albumsPerHourGoal': albumsPerHourGoal,
      'photosPerHourGoal': photosPerHourGoal,
    };
  }

  factory AiaUser.fromJson(Map<String, dynamic> json) {
    return AiaUser(
      id: json['id'] ?? 'unknown',
      name: json['name'] ?? 'Unknown User',
      role: json['role'] ?? 'Editor',
      company: json['company'] ?? 'Default',
      email: json['email'] ?? '',
      password: json['password'] ?? '',
      fullName: json['fullName'] ?? '',
      isBlocked: json['isBlocked'] ?? false,
      albumsPerHourGoal: json['albumsPerHourGoal'] ?? 5,
      photosPerHourGoal: json['photosPerHourGoal'] ?? 100,
    );
  }
}
