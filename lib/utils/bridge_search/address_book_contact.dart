/// A single phone number from the address book, alongside its vCard TYPE
/// classification ("mobile"/"work"/"home"/etc., see contacts-sync's own
/// contact-compiler.py label_from_type) - kept alongside the number rather
/// than a bare string so the client can label ambiguous results (e.g. a
/// contact with more than one number) as "Chris Moore (work)" instead of
/// just "Chris Moore".
class AddressBookPhone {
  final String value;
  final String label;

  AddressBookPhone({required this.value, required this.label});

  factory AddressBookPhone.fromJson(Map<String, Object?> json) =>
      AddressBookPhone(
        value: json['value'] as String,
        label: (json['label'] as String?) ?? '',
      );
}

class AddressBookContact {
  final String name;
  final List<AddressBookPhone> phones;
  final List<String> emails;

  AddressBookContact({
    required this.name,
    this.phones = const [],
    this.emails = const [],
  });

  factory AddressBookContact.fromJson(Map<String, Object?> json) =>
      AddressBookContact(
        name: json['name'] as String,
        phones: (json['phones'] as List?)
                ?.map((p) => AddressBookPhone.fromJson((p as Map).cast()))
                .toList() ??
            const [],
        emails: (json['emails'] as List?)?.cast<String>() ?? const [],
      );
}
