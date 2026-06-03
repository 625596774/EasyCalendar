import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('节日规则来源 JSON 覆盖内置规则且来源引用有效', () {
    final file = File('assets/data/festivals/festival_rules.json');
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final sources = json['sources'] as Map<String, dynamic>;
    final ruleGroups = [
      ...(json['solarFixedFestivals'] as List<dynamic>),
      ...(json['weekBasedFestivals'] as List<dynamic>),
      ...(json['lunarFestivals'] as List<dynamic>),
    ].cast<Map<String, dynamic>>();
    final names = ruleGroups.map((rule) => rule['name'] as String).toSet();

    expect(json['schemaVersion'], 1);
    expect(sources, isNotEmpty);
    expect(
      names,
      containsAll({
        '元旦',
        '情人节',
        '劳动节',
        '国庆节',
        '万圣节',
        '圣诞节',
        '母亲节',
        '父亲节',
        '感恩节',
        '春节',
        '元宵节',
        '端午节',
        '七夕',
        '中秋节',
        '重阳节',
        '除夕',
      }),
    );

    for (final rule in ruleGroups) {
      final sourceRefs = (rule['sourceRefs'] as List<dynamic>).cast<String>();
      expect(sourceRefs, isNotEmpty, reason: '${rule['name']} 缺少来源引用');
      for (final sourceRef in sourceRefs) {
        expect(
          sources.containsKey(sourceRef),
          isTrue,
          reason: '${rule['name']} 引用了不存在的来源 $sourceRef',
        );
      }
    }
  });
}
