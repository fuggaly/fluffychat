class AddressBookContact {
  final String name;
  final List<String> phones;
  final List<String> emails;

  AddressBookContact({
    required this.name,
    this.phones = const [],
    this.emails = const [],
  });

  factory AddressBookContact.fromJson(Map<String, Object?> json) =>
      AddressBookContact(
        name: json['name'] as String,
        phones: (json['phones'] as List?)?.cast<String>() ?? const [],
        emails: (json['emails'] as List?)?.cast<String>() ?? const [],
      );
}
