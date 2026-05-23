import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/particulier/securityregister.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_maps_webservice/places.dart';

class Country {
  final String name;
  final String dialCode;
  final String code;

  Country({required this.name, required this.dialCode, required this.code});

  factory Country.fromJson(Map<String, dynamic> json) {
    return Country(
      name: json['name'] as String,
      dialCode: json['dial_code'] as String,
      code: json['code'] as String,
    );
  }
}

Future<List<Country>> loadCountries() async {
  final String response = await rootBundle.loadString('assets/CountryCodes.json');
  final data = await json.decode(response) as List;
  return data.map((item) => Country.fromJson(item)).toList();
}

class RegisterPhoneAdressInformationPage extends StatefulWidget {
  const RegisterPhoneAdressInformationPage({super.key});

  @override
  State<RegisterPhoneAdressInformationPage> createState() =>
      _RegisterPhoneAdressInformationPageState();
}

class _RegisterPhoneAdressInformationPageState
    extends State<RegisterPhoneAdressInformationPage> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  String _selectedCountryCode = '+33';

  List<Country> countries = [];
  Country? selectedCountry;

  bool _isPhoneValid = true;
  bool _isAddressValid = true;

  static const _green = Color(0xFF6E9E57);
  static const _teal = Color(0xFF0C5C6C);
  static const _bg = Color(0xFFF8F8F6);

  @override
  void initState() {
    super.initState();
    loadCountries().then((list) {
      setState(() {
        countries = list;
        selectedCountry = countries.isNotEmpty ? countries[0] : null;
      });
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  void _validateAndContinue() {
    setState(() {
      _isPhoneValid = _phoneController.text.trim().isNotEmpty;
      _isAddressValid = _addressController.text.trim().isNotEmpty;
    });
    if (!_isPhoneValid || !_isAddressValid) return;

    User_Info.phone_number = _phoneController.text;
    User_Info.codeISO = _selectedCountryCode;
    User_Info.adress = _addressController.text;

    Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterSecurity()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Inscription',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: const _StepBar(current: 2, total: 3),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Vos coordonnées',
              style: TextStyle(
                  fontFamily: 'Galey',
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                  color: Color(0xFF1F2A2E))),
          const SizedBox(height: 6),
          Text('Renseignez votre numéro de téléphone et votre adresse.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade500)),
          const SizedBox(height: 24),

          // ── Téléphone ─────────────────────────────────────────────────────────
          _card([
            Text('Numéro de téléphone',
                style: TextStyle(
                    fontFamily: 'Galey',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700)),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                border: Border.all(
                    color: _isPhoneValid ? const Color(0xFFE4E7E2) : Colors.red),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  // Country code dropdown
                  if (countries.isNotEmpty)
                    IntrinsicWidth(
                      child: DropdownButtonHideUnderline(
                        child: ButtonTheme(
                          alignedDropdown: true,
                          child: DropdownButton<Country>(
                            value: selectedCountry,
                            icon: const Icon(Icons.keyboard_arrow_down,
                                size: 18, color: Color(0xFF6F767B)),
                            isDense: true,
                            onChanged: (Country? v) {
                              setState(() {
                                selectedCountry = v!;
                                _selectedCountryCode = v.dialCode;
                              });
                            },
                            items: countries.map((c) {
                              return DropdownMenuItem<Country>(
                                value: c,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Image.asset(
                                      'assets/country/${c.code.toLowerCase()}.png',
                                      width: 20,
                                      height: 14,
                                      errorBuilder: (_, __, ___) =>
                                          const Icon(Icons.flag, size: 18),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(c.dialCode,
                                        style: const TextStyle(
                                            fontFamily: 'Galey', fontSize: 13)),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(_selectedCountryCode,
                          style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                    ),
                  Container(width: 1, height: 36, color: const Color(0xFFE4E7E2)),
                  Expanded(
                    child: TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        isDense: true,
                        hintText: 'Numéro de téléphone',
                        hintStyle: TextStyle(
                            fontFamily: 'Galey',
                            fontSize: 13,
                            color: Color(0xFF6F767B)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (!_isPhoneValid)
              const Padding(
                padding: EdgeInsets.only(top: 4, left: 4),
                child: Text('Numéro requis',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.red)),
              ),
          ]),
          const SizedBox(height: 16),

          // ── Adresse ───────────────────────────────────────────────────────────
          _card([
            Text('Adresse',
                style: TextStyle(
                    fontFamily: 'Galey',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700)),
            const SizedBox(height: 10),
            PlacesSearchWidget(
                controller: _addressController, isValid: _isAddressValid),
          ]),
          const SizedBox(height: 32),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _validateAndContinue,
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('CONTINUER',
                  style: TextStyle(
                      fontFamily: 'Galey',
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: Colors.white)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _card(List<Widget> children) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 6,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );
}

class PlacesSearchWidget extends StatefulWidget {
  final TextEditingController controller;
  final bool isValid;

  const PlacesSearchWidget({super.key, required this.controller, required this.isValid});

  @override
  _PlacesSearchWidgetState createState() => _PlacesSearchWidgetState();
}

class _PlacesSearchWidgetState extends State<PlacesSearchWidget> {
  final GoogleMapsPlaces _places = GoogleMapsPlaces(apiKey: getApiKey());
  List<Prediction> _suggestions = [];
  String _lastText = '';

  static const _green = Color(0xFF6E9E57);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final text = widget.controller.text;
    if (text == _lastText) return;
    _lastText = text;
    if (text.isEmpty) {
      setState(() => _suggestions = []);
    } else {
      _getSuggestions(text);
    }
  }

  Future<void> _getSuggestions(String input) async {
    final response = await _places.autocomplete(input);
    if (!mounted) return;
    if (response.isOkay) {
      setState(() => _suggestions = response.predictions);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: widget.controller,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Entrez votre adresse',
            hintStyle:
                const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B)),
            prefixIcon: const Icon(Icons.place_outlined, size: 18, color: Color(0xFF6F767B)),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                    color: widget.isValid ? const Color(0xFFE4E7E2) : Colors.red)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _green, width: 1.5)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            isDense: true,
          ),
        ),
        if (!widget.isValid)
          const Padding(
            padding: EdgeInsets.only(top: 4, left: 4),
            child: Text('Adresse requise',
                style:
                    TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.red)),
          ),
        if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE4E7E2)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 3))
              ],
            ),
            child: ListView.separated(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _suggestions.length > 4 ? 4 : _suggestions.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF0F0F0)),
              itemBuilder: (context, index) {
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.place_outlined, size: 18, color: Color(0xFF6F767B)),
                  title: Text(
                    _suggestions[index].description ?? '',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
                  ),
                  onTap: () {
                    final desc = _suggestions[index].description ?? '';
                    _lastText = desc;
                    widget.controller.text = desc;
                    User_Info.adress = desc;
                    FocusScope.of(context).unfocus();
                    setState(() => _suggestions = []);
                  },
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onSearchChanged);
    _places.dispose();
    super.dispose();
  }
}

class _StepBar extends StatelessWidget {
  final int current;
  final int total;
  const _StepBar({required this.current, required this.total});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Row(
          children: List.generate(
            total,
            (i) => Expanded(
              child: Container(
                height: 3,
                margin: EdgeInsets.only(right: i < total - 1 ? 4 : 0),
                decoration: BoxDecoration(
                  color: i < current ? Colors.white : Colors.white38,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
      );
}
