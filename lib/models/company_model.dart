class Company {
  final String id;
  final String name;
  final String contactName;
  final String contactInfo; // Email/Phone
  final String city;
  final String state;
  final String country;
  final bool isBlocked;

  Company({
    required this.id,
    required this.name,
    this.contactName = "",
    this.contactInfo = "",
    this.city = "",
    this.state = "",
    this.country = "",
    this.isBlocked = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'contactName': contactName,
      'contactInfo': contactInfo,
      'city': city,
      'state': state,
      'country': country,
      'isBlocked': isBlocked,
    };
  }

  factory Company.fromJson(Map<String, dynamic> json) {
    return Company(
      id: json['id'] ?? 'unknown',
      name: json['name'] ?? 'Unnamed Company',
      contactName: json['contactName'] ?? '',
      contactInfo: json['contactInfo'] ?? '',
      city: json['city'] ?? '',
      state: json['state'] ?? '',
      country: json['country'] ?? '',
      isBlocked: json['isBlocked'] ?? false,
    );
  }
}
