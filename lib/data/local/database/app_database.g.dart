// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $SettingsTable extends Settings with TableInfo<$SettingsTable, Setting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _ageTierMeta =
      const VerificationMeta('ageTier');
  @override
  late final GeneratedColumn<int> ageTier = GeneratedColumn<int>(
      'age_tier', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _nightBoundaryHourMeta =
      const VerificationMeta('nightBoundaryHour');
  @override
  late final GeneratedColumn<int> nightBoundaryHour = GeneratedColumn<int>(
      'night_boundary_hour', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(kNightBoundaryDefaultHour));
  static const VerificationMeta _nightBoundaryMinuteMeta =
      const VerificationMeta('nightBoundaryMinute');
  @override
  late final GeneratedColumn<int> nightBoundaryMinute = GeneratedColumn<int>(
      'night_boundary_minute', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _dailyFocusCapMeta =
      const VerificationMeta('dailyFocusCap');
  @override
  late final GeneratedColumn<int> dailyFocusCap = GeneratedColumn<int>(
      'daily_focus_cap', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _dailyAppCapMinutesMeta =
      const VerificationMeta('dailyAppCapMinutes');
  @override
  late final GeneratedColumn<int> dailyAppCapMinutes = GeneratedColumn<int>(
      'daily_app_cap_minutes', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _restAfterSessionsMeta =
      const VerificationMeta('restAfterSessions');
  @override
  late final GeneratedColumn<int> restAfterSessions = GeneratedColumn<int>(
      'rest_after_sessions', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _restMinutesMeta =
      const VerificationMeta('restMinutes');
  @override
  late final GeneratedColumn<int> restMinutes = GeneratedColumn<int>(
      'rest_minutes', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _taskSunlightMeta =
      const VerificationMeta('taskSunlight');
  @override
  late final GeneratedColumn<int> taskSunlight = GeneratedColumn<int>(
      'task_sunlight', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _monthlyPoolBudgetMeta =
      const VerificationMeta('monthlyPoolBudget');
  @override
  late final GeneratedColumn<int> monthlyPoolBudget = GeneratedColumn<int>(
      'monthly_pool_budget', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _quietModeMeta =
      const VerificationMeta('quietMode');
  @override
  late final GeneratedColumn<bool> quietMode = GeneratedColumn<bool>(
      'quiet_mode', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("quiet_mode" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _soundOnMeta =
      const VerificationMeta('soundOn');
  @override
  late final GeneratedColumn<bool> soundOn = GeneratedColumn<bool>(
      'sound_on', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("sound_on" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _bgmOnMeta = const VerificationMeta('bgmOn');
  @override
  late final GeneratedColumn<bool> bgmOn = GeneratedColumn<bool>(
      'bgm_on', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("bgm_on" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _detectionOnMeta =
      const VerificationMeta('detectionOn');
  @override
  late final GeneratedColumn<bool> detectionOn = GeneratedColumn<bool>(
      'detection_on', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("detection_on" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _autoConfirmSingleHighMeta =
      const VerificationMeta('autoConfirmSingleHigh');
  @override
  late final GeneratedColumn<int> autoConfirmSingleHigh = GeneratedColumn<int>(
      'auto_confirm_single_high', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(kAutoApproveMaxCostHigh));
  static const VerificationMeta _autoConfirmSingleLowMeta =
      const VerificationMeta('autoConfirmSingleLow');
  @override
  late final GeneratedColumn<int> autoConfirmSingleLow = GeneratedColumn<int>(
      'auto_confirm_single_low', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(kAutoApproveMaxCostLow));
  static const VerificationMeta _autoConfirmMonthlyPctMeta =
      const VerificationMeta('autoConfirmMonthlyPct');
  @override
  late final GeneratedColumn<double> autoConfirmMonthlyPct =
      GeneratedColumn<double>('auto_confirm_monthly_pct', aliasedName, false,
          type: DriftSqlType.double,
          requiredDuringInsert: false,
          defaultValue: const Constant(kAutoApprovePoolRatio));
  static const VerificationMeta _currencyRateMeta =
      const VerificationMeta('currencyRate');
  @override
  late final GeneratedColumn<double> currencyRate = GeneratedColumn<double>(
      'currency_rate', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(kAutoApprovePoolRatio));
  static const VerificationMeta _themeDarkMeta =
      const VerificationMeta('themeDark');
  @override
  late final GeneratedColumn<bool> themeDark = GeneratedColumn<bool>(
      'theme_dark', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("theme_dark" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _autonomousModeMeta =
      const VerificationMeta('autonomousMode');
  @override
  late final GeneratedColumn<bool> autonomousMode = GeneratedColumn<bool>(
      'autonomous_mode', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("autonomous_mode" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _gardenPotCapacityMeta =
      const VerificationMeta('gardenPotCapacity');
  @override
  late final GeneratedColumn<int> gardenPotCapacity = GeneratedColumn<int>(
      'garden_pot_capacity', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(kGardenPotCapacityDefault));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        ageTier,
        nightBoundaryHour,
        nightBoundaryMinute,
        dailyFocusCap,
        dailyAppCapMinutes,
        restAfterSessions,
        restMinutes,
        taskSunlight,
        monthlyPoolBudget,
        quietMode,
        soundOn,
        bgmOn,
        detectionOn,
        autoConfirmSingleHigh,
        autoConfirmSingleLow,
        autoConfirmMonthlyPct,
        currencyRate,
        themeDark,
        autonomousMode,
        gardenPotCapacity
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(Insertable<Setting> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('age_tier')) {
      context.handle(_ageTierMeta,
          ageTier.isAcceptableOrUnknown(data['age_tier']!, _ageTierMeta));
    } else if (isInserting) {
      context.missing(_ageTierMeta);
    }
    if (data.containsKey('night_boundary_hour')) {
      context.handle(
          _nightBoundaryHourMeta,
          nightBoundaryHour.isAcceptableOrUnknown(
              data['night_boundary_hour']!, _nightBoundaryHourMeta));
    }
    if (data.containsKey('night_boundary_minute')) {
      context.handle(
          _nightBoundaryMinuteMeta,
          nightBoundaryMinute.isAcceptableOrUnknown(
              data['night_boundary_minute']!, _nightBoundaryMinuteMeta));
    }
    if (data.containsKey('daily_focus_cap')) {
      context.handle(
          _dailyFocusCapMeta,
          dailyFocusCap.isAcceptableOrUnknown(
              data['daily_focus_cap']!, _dailyFocusCapMeta));
    } else if (isInserting) {
      context.missing(_dailyFocusCapMeta);
    }
    if (data.containsKey('daily_app_cap_minutes')) {
      context.handle(
          _dailyAppCapMinutesMeta,
          dailyAppCapMinutes.isAcceptableOrUnknown(
              data['daily_app_cap_minutes']!, _dailyAppCapMinutesMeta));
    } else if (isInserting) {
      context.missing(_dailyAppCapMinutesMeta);
    }
    if (data.containsKey('rest_after_sessions')) {
      context.handle(
          _restAfterSessionsMeta,
          restAfterSessions.isAcceptableOrUnknown(
              data['rest_after_sessions']!, _restAfterSessionsMeta));
    } else if (isInserting) {
      context.missing(_restAfterSessionsMeta);
    }
    if (data.containsKey('rest_minutes')) {
      context.handle(
          _restMinutesMeta,
          restMinutes.isAcceptableOrUnknown(
              data['rest_minutes']!, _restMinutesMeta));
    } else if (isInserting) {
      context.missing(_restMinutesMeta);
    }
    if (data.containsKey('task_sunlight')) {
      context.handle(
          _taskSunlightMeta,
          taskSunlight.isAcceptableOrUnknown(
              data['task_sunlight']!, _taskSunlightMeta));
    } else if (isInserting) {
      context.missing(_taskSunlightMeta);
    }
    if (data.containsKey('monthly_pool_budget')) {
      context.handle(
          _monthlyPoolBudgetMeta,
          monthlyPoolBudget.isAcceptableOrUnknown(
              data['monthly_pool_budget']!, _monthlyPoolBudgetMeta));
    } else if (isInserting) {
      context.missing(_monthlyPoolBudgetMeta);
    }
    if (data.containsKey('quiet_mode')) {
      context.handle(_quietModeMeta,
          quietMode.isAcceptableOrUnknown(data['quiet_mode']!, _quietModeMeta));
    }
    if (data.containsKey('sound_on')) {
      context.handle(_soundOnMeta,
          soundOn.isAcceptableOrUnknown(data['sound_on']!, _soundOnMeta));
    }
    if (data.containsKey('bgm_on')) {
      context.handle(
          _bgmOnMeta, bgmOn.isAcceptableOrUnknown(data['bgm_on']!, _bgmOnMeta));
    }
    if (data.containsKey('detection_on')) {
      context.handle(
          _detectionOnMeta,
          detectionOn.isAcceptableOrUnknown(
              data['detection_on']!, _detectionOnMeta));
    }
    if (data.containsKey('auto_confirm_single_high')) {
      context.handle(
          _autoConfirmSingleHighMeta,
          autoConfirmSingleHigh.isAcceptableOrUnknown(
              data['auto_confirm_single_high']!, _autoConfirmSingleHighMeta));
    }
    if (data.containsKey('auto_confirm_single_low')) {
      context.handle(
          _autoConfirmSingleLowMeta,
          autoConfirmSingleLow.isAcceptableOrUnknown(
              data['auto_confirm_single_low']!, _autoConfirmSingleLowMeta));
    }
    if (data.containsKey('auto_confirm_monthly_pct')) {
      context.handle(
          _autoConfirmMonthlyPctMeta,
          autoConfirmMonthlyPct.isAcceptableOrUnknown(
              data['auto_confirm_monthly_pct']!, _autoConfirmMonthlyPctMeta));
    }
    if (data.containsKey('currency_rate')) {
      context.handle(
          _currencyRateMeta,
          currencyRate.isAcceptableOrUnknown(
              data['currency_rate']!, _currencyRateMeta));
    }
    if (data.containsKey('theme_dark')) {
      context.handle(_themeDarkMeta,
          themeDark.isAcceptableOrUnknown(data['theme_dark']!, _themeDarkMeta));
    }
    if (data.containsKey('autonomous_mode')) {
      context.handle(
          _autonomousModeMeta,
          autonomousMode.isAcceptableOrUnknown(
              data['autonomous_mode']!, _autonomousModeMeta));
    }
    if (data.containsKey('garden_pot_capacity')) {
      context.handle(
          _gardenPotCapacityMeta,
          gardenPotCapacity.isAcceptableOrUnknown(
              data['garden_pot_capacity']!, _gardenPotCapacityMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Setting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Setting(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      ageTier: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}age_tier'])!,
      nightBoundaryHour: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}night_boundary_hour'])!,
      nightBoundaryMinute: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}night_boundary_minute'])!,
      dailyFocusCap: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}daily_focus_cap'])!,
      dailyAppCapMinutes: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}daily_app_cap_minutes'])!,
      restAfterSessions: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}rest_after_sessions'])!,
      restMinutes: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}rest_minutes'])!,
      taskSunlight: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}task_sunlight'])!,
      monthlyPoolBudget: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}monthly_pool_budget'])!,
      quietMode: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}quiet_mode'])!,
      soundOn: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}sound_on'])!,
      bgmOn: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}bgm_on'])!,
      detectionOn: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}detection_on'])!,
      autoConfirmSingleHigh: attachedDatabase.typeMapping.read(DriftSqlType.int,
          data['${effectivePrefix}auto_confirm_single_high'])!,
      autoConfirmSingleLow: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}auto_confirm_single_low'])!,
      autoConfirmMonthlyPct: attachedDatabase.typeMapping.read(
          DriftSqlType.double,
          data['${effectivePrefix}auto_confirm_monthly_pct'])!,
      currencyRate: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}currency_rate'])!,
      themeDark: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}theme_dark'])!,
      autonomousMode: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}autonomous_mode'])!,
      gardenPotCapacity: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}garden_pot_capacity'])!,
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class Setting extends DataClass implements Insertable<Setting> {
  final int id;
  final int ageTier;
  final int nightBoundaryHour;
  final int nightBoundaryMinute;
  final int dailyFocusCap;
  final int dailyAppCapMinutes;
  final int restAfterSessions;
  final int restMinutes;
  final int taskSunlight;
  final int monthlyPoolBudget;
  final bool quietMode;
  final bool soundOn;
  final bool bgmOn;
  final bool detectionOn;
  final int autoConfirmSingleHigh;
  final int autoConfirmSingleLow;
  final double autoConfirmMonthlyPct;
  final double currencyRate;
  final bool themeDark;
  final bool autonomousMode;
  final int gardenPotCapacity;
  const Setting(
      {required this.id,
      required this.ageTier,
      required this.nightBoundaryHour,
      required this.nightBoundaryMinute,
      required this.dailyFocusCap,
      required this.dailyAppCapMinutes,
      required this.restAfterSessions,
      required this.restMinutes,
      required this.taskSunlight,
      required this.monthlyPoolBudget,
      required this.quietMode,
      required this.soundOn,
      required this.bgmOn,
      required this.detectionOn,
      required this.autoConfirmSingleHigh,
      required this.autoConfirmSingleLow,
      required this.autoConfirmMonthlyPct,
      required this.currencyRate,
      required this.themeDark,
      required this.autonomousMode,
      required this.gardenPotCapacity});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['age_tier'] = Variable<int>(ageTier);
    map['night_boundary_hour'] = Variable<int>(nightBoundaryHour);
    map['night_boundary_minute'] = Variable<int>(nightBoundaryMinute);
    map['daily_focus_cap'] = Variable<int>(dailyFocusCap);
    map['daily_app_cap_minutes'] = Variable<int>(dailyAppCapMinutes);
    map['rest_after_sessions'] = Variable<int>(restAfterSessions);
    map['rest_minutes'] = Variable<int>(restMinutes);
    map['task_sunlight'] = Variable<int>(taskSunlight);
    map['monthly_pool_budget'] = Variable<int>(monthlyPoolBudget);
    map['quiet_mode'] = Variable<bool>(quietMode);
    map['sound_on'] = Variable<bool>(soundOn);
    map['bgm_on'] = Variable<bool>(bgmOn);
    map['detection_on'] = Variable<bool>(detectionOn);
    map['auto_confirm_single_high'] = Variable<int>(autoConfirmSingleHigh);
    map['auto_confirm_single_low'] = Variable<int>(autoConfirmSingleLow);
    map['auto_confirm_monthly_pct'] = Variable<double>(autoConfirmMonthlyPct);
    map['currency_rate'] = Variable<double>(currencyRate);
    map['theme_dark'] = Variable<bool>(themeDark);
    map['autonomous_mode'] = Variable<bool>(autonomousMode);
    map['garden_pot_capacity'] = Variable<int>(gardenPotCapacity);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(
      id: Value(id),
      ageTier: Value(ageTier),
      nightBoundaryHour: Value(nightBoundaryHour),
      nightBoundaryMinute: Value(nightBoundaryMinute),
      dailyFocusCap: Value(dailyFocusCap),
      dailyAppCapMinutes: Value(dailyAppCapMinutes),
      restAfterSessions: Value(restAfterSessions),
      restMinutes: Value(restMinutes),
      taskSunlight: Value(taskSunlight),
      monthlyPoolBudget: Value(monthlyPoolBudget),
      quietMode: Value(quietMode),
      soundOn: Value(soundOn),
      bgmOn: Value(bgmOn),
      detectionOn: Value(detectionOn),
      autoConfirmSingleHigh: Value(autoConfirmSingleHigh),
      autoConfirmSingleLow: Value(autoConfirmSingleLow),
      autoConfirmMonthlyPct: Value(autoConfirmMonthlyPct),
      currencyRate: Value(currencyRate),
      themeDark: Value(themeDark),
      autonomousMode: Value(autonomousMode),
      gardenPotCapacity: Value(gardenPotCapacity),
    );
  }

  factory Setting.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Setting(
      id: serializer.fromJson<int>(json['id']),
      ageTier: serializer.fromJson<int>(json['ageTier']),
      nightBoundaryHour: serializer.fromJson<int>(json['nightBoundaryHour']),
      nightBoundaryMinute:
          serializer.fromJson<int>(json['nightBoundaryMinute']),
      dailyFocusCap: serializer.fromJson<int>(json['dailyFocusCap']),
      dailyAppCapMinutes: serializer.fromJson<int>(json['dailyAppCapMinutes']),
      restAfterSessions: serializer.fromJson<int>(json['restAfterSessions']),
      restMinutes: serializer.fromJson<int>(json['restMinutes']),
      taskSunlight: serializer.fromJson<int>(json['taskSunlight']),
      monthlyPoolBudget: serializer.fromJson<int>(json['monthlyPoolBudget']),
      quietMode: serializer.fromJson<bool>(json['quietMode']),
      soundOn: serializer.fromJson<bool>(json['soundOn']),
      bgmOn: serializer.fromJson<bool>(json['bgmOn']),
      detectionOn: serializer.fromJson<bool>(json['detectionOn']),
      autoConfirmSingleHigh:
          serializer.fromJson<int>(json['autoConfirmSingleHigh']),
      autoConfirmSingleLow:
          serializer.fromJson<int>(json['autoConfirmSingleLow']),
      autoConfirmMonthlyPct:
          serializer.fromJson<double>(json['autoConfirmMonthlyPct']),
      currencyRate: serializer.fromJson<double>(json['currencyRate']),
      themeDark: serializer.fromJson<bool>(json['themeDark']),
      autonomousMode: serializer.fromJson<bool>(json['autonomousMode']),
      gardenPotCapacity: serializer.fromJson<int>(json['gardenPotCapacity']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'ageTier': serializer.toJson<int>(ageTier),
      'nightBoundaryHour': serializer.toJson<int>(nightBoundaryHour),
      'nightBoundaryMinute': serializer.toJson<int>(nightBoundaryMinute),
      'dailyFocusCap': serializer.toJson<int>(dailyFocusCap),
      'dailyAppCapMinutes': serializer.toJson<int>(dailyAppCapMinutes),
      'restAfterSessions': serializer.toJson<int>(restAfterSessions),
      'restMinutes': serializer.toJson<int>(restMinutes),
      'taskSunlight': serializer.toJson<int>(taskSunlight),
      'monthlyPoolBudget': serializer.toJson<int>(monthlyPoolBudget),
      'quietMode': serializer.toJson<bool>(quietMode),
      'soundOn': serializer.toJson<bool>(soundOn),
      'bgmOn': serializer.toJson<bool>(bgmOn),
      'detectionOn': serializer.toJson<bool>(detectionOn),
      'autoConfirmSingleHigh': serializer.toJson<int>(autoConfirmSingleHigh),
      'autoConfirmSingleLow': serializer.toJson<int>(autoConfirmSingleLow),
      'autoConfirmMonthlyPct': serializer.toJson<double>(autoConfirmMonthlyPct),
      'currencyRate': serializer.toJson<double>(currencyRate),
      'themeDark': serializer.toJson<bool>(themeDark),
      'autonomousMode': serializer.toJson<bool>(autonomousMode),
      'gardenPotCapacity': serializer.toJson<int>(gardenPotCapacity),
    };
  }

  Setting copyWith(
          {int? id,
          int? ageTier,
          int? nightBoundaryHour,
          int? nightBoundaryMinute,
          int? dailyFocusCap,
          int? dailyAppCapMinutes,
          int? restAfterSessions,
          int? restMinutes,
          int? taskSunlight,
          int? monthlyPoolBudget,
          bool? quietMode,
          bool? soundOn,
          bool? bgmOn,
          bool? detectionOn,
          int? autoConfirmSingleHigh,
          int? autoConfirmSingleLow,
          double? autoConfirmMonthlyPct,
          double? currencyRate,
          bool? themeDark,
          bool? autonomousMode,
          int? gardenPotCapacity}) =>
      Setting(
        id: id ?? this.id,
        ageTier: ageTier ?? this.ageTier,
        nightBoundaryHour: nightBoundaryHour ?? this.nightBoundaryHour,
        nightBoundaryMinute: nightBoundaryMinute ?? this.nightBoundaryMinute,
        dailyFocusCap: dailyFocusCap ?? this.dailyFocusCap,
        dailyAppCapMinutes: dailyAppCapMinutes ?? this.dailyAppCapMinutes,
        restAfterSessions: restAfterSessions ?? this.restAfterSessions,
        restMinutes: restMinutes ?? this.restMinutes,
        taskSunlight: taskSunlight ?? this.taskSunlight,
        monthlyPoolBudget: monthlyPoolBudget ?? this.monthlyPoolBudget,
        quietMode: quietMode ?? this.quietMode,
        soundOn: soundOn ?? this.soundOn,
        bgmOn: bgmOn ?? this.bgmOn,
        detectionOn: detectionOn ?? this.detectionOn,
        autoConfirmSingleHigh:
            autoConfirmSingleHigh ?? this.autoConfirmSingleHigh,
        autoConfirmSingleLow: autoConfirmSingleLow ?? this.autoConfirmSingleLow,
        autoConfirmMonthlyPct:
            autoConfirmMonthlyPct ?? this.autoConfirmMonthlyPct,
        currencyRate: currencyRate ?? this.currencyRate,
        themeDark: themeDark ?? this.themeDark,
        autonomousMode: autonomousMode ?? this.autonomousMode,
        gardenPotCapacity: gardenPotCapacity ?? this.gardenPotCapacity,
      );
  Setting copyWithCompanion(SettingsCompanion data) {
    return Setting(
      id: data.id.present ? data.id.value : this.id,
      ageTier: data.ageTier.present ? data.ageTier.value : this.ageTier,
      nightBoundaryHour: data.nightBoundaryHour.present
          ? data.nightBoundaryHour.value
          : this.nightBoundaryHour,
      nightBoundaryMinute: data.nightBoundaryMinute.present
          ? data.nightBoundaryMinute.value
          : this.nightBoundaryMinute,
      dailyFocusCap: data.dailyFocusCap.present
          ? data.dailyFocusCap.value
          : this.dailyFocusCap,
      dailyAppCapMinutes: data.dailyAppCapMinutes.present
          ? data.dailyAppCapMinutes.value
          : this.dailyAppCapMinutes,
      restAfterSessions: data.restAfterSessions.present
          ? data.restAfterSessions.value
          : this.restAfterSessions,
      restMinutes:
          data.restMinutes.present ? data.restMinutes.value : this.restMinutes,
      taskSunlight: data.taskSunlight.present
          ? data.taskSunlight.value
          : this.taskSunlight,
      monthlyPoolBudget: data.monthlyPoolBudget.present
          ? data.monthlyPoolBudget.value
          : this.monthlyPoolBudget,
      quietMode: data.quietMode.present ? data.quietMode.value : this.quietMode,
      soundOn: data.soundOn.present ? data.soundOn.value : this.soundOn,
      bgmOn: data.bgmOn.present ? data.bgmOn.value : this.bgmOn,
      detectionOn:
          data.detectionOn.present ? data.detectionOn.value : this.detectionOn,
      autoConfirmSingleHigh: data.autoConfirmSingleHigh.present
          ? data.autoConfirmSingleHigh.value
          : this.autoConfirmSingleHigh,
      autoConfirmSingleLow: data.autoConfirmSingleLow.present
          ? data.autoConfirmSingleLow.value
          : this.autoConfirmSingleLow,
      autoConfirmMonthlyPct: data.autoConfirmMonthlyPct.present
          ? data.autoConfirmMonthlyPct.value
          : this.autoConfirmMonthlyPct,
      currencyRate: data.currencyRate.present
          ? data.currencyRate.value
          : this.currencyRate,
      themeDark: data.themeDark.present ? data.themeDark.value : this.themeDark,
      autonomousMode: data.autonomousMode.present
          ? data.autonomousMode.value
          : this.autonomousMode,
      gardenPotCapacity: data.gardenPotCapacity.present
          ? data.gardenPotCapacity.value
          : this.gardenPotCapacity,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Setting(')
          ..write('id: $id, ')
          ..write('ageTier: $ageTier, ')
          ..write('nightBoundaryHour: $nightBoundaryHour, ')
          ..write('nightBoundaryMinute: $nightBoundaryMinute, ')
          ..write('dailyFocusCap: $dailyFocusCap, ')
          ..write('dailyAppCapMinutes: $dailyAppCapMinutes, ')
          ..write('restAfterSessions: $restAfterSessions, ')
          ..write('restMinutes: $restMinutes, ')
          ..write('taskSunlight: $taskSunlight, ')
          ..write('monthlyPoolBudget: $monthlyPoolBudget, ')
          ..write('quietMode: $quietMode, ')
          ..write('soundOn: $soundOn, ')
          ..write('bgmOn: $bgmOn, ')
          ..write('detectionOn: $detectionOn, ')
          ..write('autoConfirmSingleHigh: $autoConfirmSingleHigh, ')
          ..write('autoConfirmSingleLow: $autoConfirmSingleLow, ')
          ..write('autoConfirmMonthlyPct: $autoConfirmMonthlyPct, ')
          ..write('currencyRate: $currencyRate, ')
          ..write('themeDark: $themeDark, ')
          ..write('autonomousMode: $autonomousMode, ')
          ..write('gardenPotCapacity: $gardenPotCapacity')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
        id,
        ageTier,
        nightBoundaryHour,
        nightBoundaryMinute,
        dailyFocusCap,
        dailyAppCapMinutes,
        restAfterSessions,
        restMinutes,
        taskSunlight,
        monthlyPoolBudget,
        quietMode,
        soundOn,
        bgmOn,
        detectionOn,
        autoConfirmSingleHigh,
        autoConfirmSingleLow,
        autoConfirmMonthlyPct,
        currencyRate,
        themeDark,
        autonomousMode,
        gardenPotCapacity
      ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Setting &&
          other.id == this.id &&
          other.ageTier == this.ageTier &&
          other.nightBoundaryHour == this.nightBoundaryHour &&
          other.nightBoundaryMinute == this.nightBoundaryMinute &&
          other.dailyFocusCap == this.dailyFocusCap &&
          other.dailyAppCapMinutes == this.dailyAppCapMinutes &&
          other.restAfterSessions == this.restAfterSessions &&
          other.restMinutes == this.restMinutes &&
          other.taskSunlight == this.taskSunlight &&
          other.monthlyPoolBudget == this.monthlyPoolBudget &&
          other.quietMode == this.quietMode &&
          other.soundOn == this.soundOn &&
          other.bgmOn == this.bgmOn &&
          other.detectionOn == this.detectionOn &&
          other.autoConfirmSingleHigh == this.autoConfirmSingleHigh &&
          other.autoConfirmSingleLow == this.autoConfirmSingleLow &&
          other.autoConfirmMonthlyPct == this.autoConfirmMonthlyPct &&
          other.currencyRate == this.currencyRate &&
          other.themeDark == this.themeDark &&
          other.autonomousMode == this.autonomousMode &&
          other.gardenPotCapacity == this.gardenPotCapacity);
}

class SettingsCompanion extends UpdateCompanion<Setting> {
  final Value<int> id;
  final Value<int> ageTier;
  final Value<int> nightBoundaryHour;
  final Value<int> nightBoundaryMinute;
  final Value<int> dailyFocusCap;
  final Value<int> dailyAppCapMinutes;
  final Value<int> restAfterSessions;
  final Value<int> restMinutes;
  final Value<int> taskSunlight;
  final Value<int> monthlyPoolBudget;
  final Value<bool> quietMode;
  final Value<bool> soundOn;
  final Value<bool> bgmOn;
  final Value<bool> detectionOn;
  final Value<int> autoConfirmSingleHigh;
  final Value<int> autoConfirmSingleLow;
  final Value<double> autoConfirmMonthlyPct;
  final Value<double> currencyRate;
  final Value<bool> themeDark;
  final Value<bool> autonomousMode;
  final Value<int> gardenPotCapacity;
  const SettingsCompanion({
    this.id = const Value.absent(),
    this.ageTier = const Value.absent(),
    this.nightBoundaryHour = const Value.absent(),
    this.nightBoundaryMinute = const Value.absent(),
    this.dailyFocusCap = const Value.absent(),
    this.dailyAppCapMinutes = const Value.absent(),
    this.restAfterSessions = const Value.absent(),
    this.restMinutes = const Value.absent(),
    this.taskSunlight = const Value.absent(),
    this.monthlyPoolBudget = const Value.absent(),
    this.quietMode = const Value.absent(),
    this.soundOn = const Value.absent(),
    this.bgmOn = const Value.absent(),
    this.detectionOn = const Value.absent(),
    this.autoConfirmSingleHigh = const Value.absent(),
    this.autoConfirmSingleLow = const Value.absent(),
    this.autoConfirmMonthlyPct = const Value.absent(),
    this.currencyRate = const Value.absent(),
    this.themeDark = const Value.absent(),
    this.autonomousMode = const Value.absent(),
    this.gardenPotCapacity = const Value.absent(),
  });
  SettingsCompanion.insert({
    this.id = const Value.absent(),
    required int ageTier,
    this.nightBoundaryHour = const Value.absent(),
    this.nightBoundaryMinute = const Value.absent(),
    required int dailyFocusCap,
    required int dailyAppCapMinutes,
    required int restAfterSessions,
    required int restMinutes,
    required int taskSunlight,
    required int monthlyPoolBudget,
    this.quietMode = const Value.absent(),
    this.soundOn = const Value.absent(),
    this.bgmOn = const Value.absent(),
    this.detectionOn = const Value.absent(),
    this.autoConfirmSingleHigh = const Value.absent(),
    this.autoConfirmSingleLow = const Value.absent(),
    this.autoConfirmMonthlyPct = const Value.absent(),
    this.currencyRate = const Value.absent(),
    this.themeDark = const Value.absent(),
    this.autonomousMode = const Value.absent(),
    this.gardenPotCapacity = const Value.absent(),
  })  : ageTier = Value(ageTier),
        dailyFocusCap = Value(dailyFocusCap),
        dailyAppCapMinutes = Value(dailyAppCapMinutes),
        restAfterSessions = Value(restAfterSessions),
        restMinutes = Value(restMinutes),
        taskSunlight = Value(taskSunlight),
        monthlyPoolBudget = Value(monthlyPoolBudget);
  static Insertable<Setting> custom({
    Expression<int>? id,
    Expression<int>? ageTier,
    Expression<int>? nightBoundaryHour,
    Expression<int>? nightBoundaryMinute,
    Expression<int>? dailyFocusCap,
    Expression<int>? dailyAppCapMinutes,
    Expression<int>? restAfterSessions,
    Expression<int>? restMinutes,
    Expression<int>? taskSunlight,
    Expression<int>? monthlyPoolBudget,
    Expression<bool>? quietMode,
    Expression<bool>? soundOn,
    Expression<bool>? bgmOn,
    Expression<bool>? detectionOn,
    Expression<int>? autoConfirmSingleHigh,
    Expression<int>? autoConfirmSingleLow,
    Expression<double>? autoConfirmMonthlyPct,
    Expression<double>? currencyRate,
    Expression<bool>? themeDark,
    Expression<bool>? autonomousMode,
    Expression<int>? gardenPotCapacity,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ageTier != null) 'age_tier': ageTier,
      if (nightBoundaryHour != null) 'night_boundary_hour': nightBoundaryHour,
      if (nightBoundaryMinute != null)
        'night_boundary_minute': nightBoundaryMinute,
      if (dailyFocusCap != null) 'daily_focus_cap': dailyFocusCap,
      if (dailyAppCapMinutes != null)
        'daily_app_cap_minutes': dailyAppCapMinutes,
      if (restAfterSessions != null) 'rest_after_sessions': restAfterSessions,
      if (restMinutes != null) 'rest_minutes': restMinutes,
      if (taskSunlight != null) 'task_sunlight': taskSunlight,
      if (monthlyPoolBudget != null) 'monthly_pool_budget': monthlyPoolBudget,
      if (quietMode != null) 'quiet_mode': quietMode,
      if (soundOn != null) 'sound_on': soundOn,
      if (bgmOn != null) 'bgm_on': bgmOn,
      if (detectionOn != null) 'detection_on': detectionOn,
      if (autoConfirmSingleHigh != null)
        'auto_confirm_single_high': autoConfirmSingleHigh,
      if (autoConfirmSingleLow != null)
        'auto_confirm_single_low': autoConfirmSingleLow,
      if (autoConfirmMonthlyPct != null)
        'auto_confirm_monthly_pct': autoConfirmMonthlyPct,
      if (currencyRate != null) 'currency_rate': currencyRate,
      if (themeDark != null) 'theme_dark': themeDark,
      if (autonomousMode != null) 'autonomous_mode': autonomousMode,
      if (gardenPotCapacity != null) 'garden_pot_capacity': gardenPotCapacity,
    });
  }

  SettingsCompanion copyWith(
      {Value<int>? id,
      Value<int>? ageTier,
      Value<int>? nightBoundaryHour,
      Value<int>? nightBoundaryMinute,
      Value<int>? dailyFocusCap,
      Value<int>? dailyAppCapMinutes,
      Value<int>? restAfterSessions,
      Value<int>? restMinutes,
      Value<int>? taskSunlight,
      Value<int>? monthlyPoolBudget,
      Value<bool>? quietMode,
      Value<bool>? soundOn,
      Value<bool>? bgmOn,
      Value<bool>? detectionOn,
      Value<int>? autoConfirmSingleHigh,
      Value<int>? autoConfirmSingleLow,
      Value<double>? autoConfirmMonthlyPct,
      Value<double>? currencyRate,
      Value<bool>? themeDark,
      Value<bool>? autonomousMode,
      Value<int>? gardenPotCapacity}) {
    return SettingsCompanion(
      id: id ?? this.id,
      ageTier: ageTier ?? this.ageTier,
      nightBoundaryHour: nightBoundaryHour ?? this.nightBoundaryHour,
      nightBoundaryMinute: nightBoundaryMinute ?? this.nightBoundaryMinute,
      dailyFocusCap: dailyFocusCap ?? this.dailyFocusCap,
      dailyAppCapMinutes: dailyAppCapMinutes ?? this.dailyAppCapMinutes,
      restAfterSessions: restAfterSessions ?? this.restAfterSessions,
      restMinutes: restMinutes ?? this.restMinutes,
      taskSunlight: taskSunlight ?? this.taskSunlight,
      monthlyPoolBudget: monthlyPoolBudget ?? this.monthlyPoolBudget,
      quietMode: quietMode ?? this.quietMode,
      soundOn: soundOn ?? this.soundOn,
      bgmOn: bgmOn ?? this.bgmOn,
      detectionOn: detectionOn ?? this.detectionOn,
      autoConfirmSingleHigh:
          autoConfirmSingleHigh ?? this.autoConfirmSingleHigh,
      autoConfirmSingleLow: autoConfirmSingleLow ?? this.autoConfirmSingleLow,
      autoConfirmMonthlyPct:
          autoConfirmMonthlyPct ?? this.autoConfirmMonthlyPct,
      currencyRate: currencyRate ?? this.currencyRate,
      themeDark: themeDark ?? this.themeDark,
      autonomousMode: autonomousMode ?? this.autonomousMode,
      gardenPotCapacity: gardenPotCapacity ?? this.gardenPotCapacity,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (ageTier.present) {
      map['age_tier'] = Variable<int>(ageTier.value);
    }
    if (nightBoundaryHour.present) {
      map['night_boundary_hour'] = Variable<int>(nightBoundaryHour.value);
    }
    if (nightBoundaryMinute.present) {
      map['night_boundary_minute'] = Variable<int>(nightBoundaryMinute.value);
    }
    if (dailyFocusCap.present) {
      map['daily_focus_cap'] = Variable<int>(dailyFocusCap.value);
    }
    if (dailyAppCapMinutes.present) {
      map['daily_app_cap_minutes'] = Variable<int>(dailyAppCapMinutes.value);
    }
    if (restAfterSessions.present) {
      map['rest_after_sessions'] = Variable<int>(restAfterSessions.value);
    }
    if (restMinutes.present) {
      map['rest_minutes'] = Variable<int>(restMinutes.value);
    }
    if (taskSunlight.present) {
      map['task_sunlight'] = Variable<int>(taskSunlight.value);
    }
    if (monthlyPoolBudget.present) {
      map['monthly_pool_budget'] = Variable<int>(monthlyPoolBudget.value);
    }
    if (quietMode.present) {
      map['quiet_mode'] = Variable<bool>(quietMode.value);
    }
    if (soundOn.present) {
      map['sound_on'] = Variable<bool>(soundOn.value);
    }
    if (bgmOn.present) {
      map['bgm_on'] = Variable<bool>(bgmOn.value);
    }
    if (detectionOn.present) {
      map['detection_on'] = Variable<bool>(detectionOn.value);
    }
    if (autoConfirmSingleHigh.present) {
      map['auto_confirm_single_high'] =
          Variable<int>(autoConfirmSingleHigh.value);
    }
    if (autoConfirmSingleLow.present) {
      map['auto_confirm_single_low'] =
          Variable<int>(autoConfirmSingleLow.value);
    }
    if (autoConfirmMonthlyPct.present) {
      map['auto_confirm_monthly_pct'] =
          Variable<double>(autoConfirmMonthlyPct.value);
    }
    if (currencyRate.present) {
      map['currency_rate'] = Variable<double>(currencyRate.value);
    }
    if (themeDark.present) {
      map['theme_dark'] = Variable<bool>(themeDark.value);
    }
    if (autonomousMode.present) {
      map['autonomous_mode'] = Variable<bool>(autonomousMode.value);
    }
    if (gardenPotCapacity.present) {
      map['garden_pot_capacity'] = Variable<int>(gardenPotCapacity.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('id: $id, ')
          ..write('ageTier: $ageTier, ')
          ..write('nightBoundaryHour: $nightBoundaryHour, ')
          ..write('nightBoundaryMinute: $nightBoundaryMinute, ')
          ..write('dailyFocusCap: $dailyFocusCap, ')
          ..write('dailyAppCapMinutes: $dailyAppCapMinutes, ')
          ..write('restAfterSessions: $restAfterSessions, ')
          ..write('restMinutes: $restMinutes, ')
          ..write('taskSunlight: $taskSunlight, ')
          ..write('monthlyPoolBudget: $monthlyPoolBudget, ')
          ..write('quietMode: $quietMode, ')
          ..write('soundOn: $soundOn, ')
          ..write('bgmOn: $bgmOn, ')
          ..write('detectionOn: $detectionOn, ')
          ..write('autoConfirmSingleHigh: $autoConfirmSingleHigh, ')
          ..write('autoConfirmSingleLow: $autoConfirmSingleLow, ')
          ..write('autoConfirmMonthlyPct: $autoConfirmMonthlyPct, ')
          ..write('currencyRate: $currencyRate, ')
          ..write('themeDark: $themeDark, ')
          ..write('autonomousMode: $autonomousMode, ')
          ..write('gardenPotCapacity: $gardenPotCapacity')
          ..write(')'))
        .toString();
  }
}

class $PlantsTable extends Plants with TableInfo<$PlantsTable, Plant> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlantsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _speciesIdMeta =
      const VerificationMeta('speciesId');
  @override
  late final GeneratedColumn<String> speciesId = GeneratedColumn<String>(
      'species_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _potIndexMeta =
      const VerificationMeta('potIndex');
  @override
  late final GeneratedColumn<int> potIndex = GeneratedColumn<int>(
      'pot_index', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _stageMeta = const VerificationMeta('stage');
  @override
  late final GeneratedColumn<int> stage = GeneratedColumn<int>(
      'stage', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _stageStartedAtMeta =
      const VerificationMeta('stageStartedAt');
  @override
  late final GeneratedColumn<DateTime> stageStartedAt =
      GeneratedColumn<DateTime>('stage_started_at', aliasedName, false,
          type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _growthProgressMeta =
      const VerificationMeta('growthProgress');
  @override
  late final GeneratedColumn<double> growthProgress = GeneratedColumn<double>(
      'growth_progress', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(0.0));
  static const VerificationMeta _growthFactorMeta =
      const VerificationMeta('growthFactor');
  @override
  late final GeneratedColumn<double> growthFactor = GeneratedColumn<double>(
      'growth_factor', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(1.0));
  static const VerificationMeta _waterUsedMeta =
      const VerificationMeta('waterUsed');
  @override
  late final GeneratedColumn<bool> waterUsed = GeneratedColumn<bool>(
      'water_used', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("water_used" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _fertilizerUsedMeta =
      const VerificationMeta('fertilizerUsed');
  @override
  late final GeneratedColumn<bool> fertilizerUsed = GeneratedColumn<bool>(
      'fertilizer_used', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("fertilizer_used" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<int> status = GeneratedColumn<int>(
      'status', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _plantedAtMeta =
      const VerificationMeta('plantedAt');
  @override
  late final GeneratedColumn<DateTime> plantedAt = GeneratedColumn<DateTime>(
      'planted_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _lastWaterAtMeta =
      const VerificationMeta('lastWaterAt');
  @override
  late final GeneratedColumn<DateTime> lastWaterAt = GeneratedColumn<DateTime>(
      'last_water_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _wiltedAtMeta =
      const VerificationMeta('wiltedAt');
  @override
  late final GeneratedColumn<DateTime> wiltedAt = GeneratedColumn<DateTime>(
      'wilted_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _deadAtMeta = const VerificationMeta('deadAt');
  @override
  late final GeneratedColumn<DateTime> deadAt = GeneratedColumn<DateTime>(
      'dead_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _bloomedAtMeta =
      const VerificationMeta('bloomedAt');
  @override
  late final GeneratedColumn<DateTime> bloomedAt = GeneratedColumn<DateTime>(
      'bloomed_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _moodMeta = const VerificationMeta('mood');
  @override
  late final GeneratedColumn<int> mood = GeneratedColumn<int>(
      'mood', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        speciesId,
        potIndex,
        stage,
        stageStartedAt,
        growthProgress,
        growthFactor,
        waterUsed,
        fertilizerUsed,
        status,
        plantedAt,
        lastWaterAt,
        wiltedAt,
        deadAt,
        bloomedAt,
        mood
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'plants';
  @override
  VerificationContext validateIntegrity(Insertable<Plant> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('species_id')) {
      context.handle(_speciesIdMeta,
          speciesId.isAcceptableOrUnknown(data['species_id']!, _speciesIdMeta));
    } else if (isInserting) {
      context.missing(_speciesIdMeta);
    }
    if (data.containsKey('pot_index')) {
      context.handle(_potIndexMeta,
          potIndex.isAcceptableOrUnknown(data['pot_index']!, _potIndexMeta));
    } else if (isInserting) {
      context.missing(_potIndexMeta);
    }
    if (data.containsKey('stage')) {
      context.handle(
          _stageMeta, stage.isAcceptableOrUnknown(data['stage']!, _stageMeta));
    } else if (isInserting) {
      context.missing(_stageMeta);
    }
    if (data.containsKey('stage_started_at')) {
      context.handle(
          _stageStartedAtMeta,
          stageStartedAt.isAcceptableOrUnknown(
              data['stage_started_at']!, _stageStartedAtMeta));
    } else if (isInserting) {
      context.missing(_stageStartedAtMeta);
    }
    if (data.containsKey('growth_progress')) {
      context.handle(
          _growthProgressMeta,
          growthProgress.isAcceptableOrUnknown(
              data['growth_progress']!, _growthProgressMeta));
    }
    if (data.containsKey('growth_factor')) {
      context.handle(
          _growthFactorMeta,
          growthFactor.isAcceptableOrUnknown(
              data['growth_factor']!, _growthFactorMeta));
    }
    if (data.containsKey('water_used')) {
      context.handle(_waterUsedMeta,
          waterUsed.isAcceptableOrUnknown(data['water_used']!, _waterUsedMeta));
    }
    if (data.containsKey('fertilizer_used')) {
      context.handle(
          _fertilizerUsedMeta,
          fertilizerUsed.isAcceptableOrUnknown(
              data['fertilizer_used']!, _fertilizerUsedMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('planted_at')) {
      context.handle(_plantedAtMeta,
          plantedAt.isAcceptableOrUnknown(data['planted_at']!, _plantedAtMeta));
    } else if (isInserting) {
      context.missing(_plantedAtMeta);
    }
    if (data.containsKey('last_water_at')) {
      context.handle(
          _lastWaterAtMeta,
          lastWaterAt.isAcceptableOrUnknown(
              data['last_water_at']!, _lastWaterAtMeta));
    }
    if (data.containsKey('wilted_at')) {
      context.handle(_wiltedAtMeta,
          wiltedAt.isAcceptableOrUnknown(data['wilted_at']!, _wiltedAtMeta));
    }
    if (data.containsKey('dead_at')) {
      context.handle(_deadAtMeta,
          deadAt.isAcceptableOrUnknown(data['dead_at']!, _deadAtMeta));
    }
    if (data.containsKey('bloomed_at')) {
      context.handle(_bloomedAtMeta,
          bloomedAt.isAcceptableOrUnknown(data['bloomed_at']!, _bloomedAtMeta));
    }
    if (data.containsKey('mood')) {
      context.handle(
          _moodMeta, mood.isAcceptableOrUnknown(data['mood']!, _moodMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Plant map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Plant(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      speciesId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}species_id'])!,
      potIndex: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}pot_index'])!,
      stage: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}stage'])!,
      stageStartedAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}stage_started_at'])!,
      growthProgress: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}growth_progress'])!,
      growthFactor: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}growth_factor'])!,
      waterUsed: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}water_used'])!,
      fertilizerUsed: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}fertilizer_used'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}status'])!,
      plantedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}planted_at'])!,
      lastWaterAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}last_water_at']),
      wiltedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}wilted_at']),
      deadAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}dead_at']),
      bloomedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}bloomed_at']),
      mood: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}mood'])!,
    );
  }

  @override
  $PlantsTable createAlias(String alias) {
    return $PlantsTable(attachedDatabase, alias);
  }
}

class Plant extends DataClass implements Insertable<Plant> {
  final String id;
  final String speciesId;
  final int potIndex;
  final int stage;
  final DateTime stageStartedAt;
  final double growthProgress;
  final double growthFactor;
  final bool waterUsed;
  final bool fertilizerUsed;
  final int status;
  final DateTime plantedAt;
  final DateTime? lastWaterAt;
  final DateTime? wiltedAt;
  final DateTime? deadAt;
  final DateTime? bloomedAt;
  final int mood;
  const Plant(
      {required this.id,
      required this.speciesId,
      required this.potIndex,
      required this.stage,
      required this.stageStartedAt,
      required this.growthProgress,
      required this.growthFactor,
      required this.waterUsed,
      required this.fertilizerUsed,
      required this.status,
      required this.plantedAt,
      this.lastWaterAt,
      this.wiltedAt,
      this.deadAt,
      this.bloomedAt,
      required this.mood});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['species_id'] = Variable<String>(speciesId);
    map['pot_index'] = Variable<int>(potIndex);
    map['stage'] = Variable<int>(stage);
    map['stage_started_at'] = Variable<DateTime>(stageStartedAt);
    map['growth_progress'] = Variable<double>(growthProgress);
    map['growth_factor'] = Variable<double>(growthFactor);
    map['water_used'] = Variable<bool>(waterUsed);
    map['fertilizer_used'] = Variable<bool>(fertilizerUsed);
    map['status'] = Variable<int>(status);
    map['planted_at'] = Variable<DateTime>(plantedAt);
    if (!nullToAbsent || lastWaterAt != null) {
      map['last_water_at'] = Variable<DateTime>(lastWaterAt);
    }
    if (!nullToAbsent || wiltedAt != null) {
      map['wilted_at'] = Variable<DateTime>(wiltedAt);
    }
    if (!nullToAbsent || deadAt != null) {
      map['dead_at'] = Variable<DateTime>(deadAt);
    }
    if (!nullToAbsent || bloomedAt != null) {
      map['bloomed_at'] = Variable<DateTime>(bloomedAt);
    }
    map['mood'] = Variable<int>(mood);
    return map;
  }

  PlantsCompanion toCompanion(bool nullToAbsent) {
    return PlantsCompanion(
      id: Value(id),
      speciesId: Value(speciesId),
      potIndex: Value(potIndex),
      stage: Value(stage),
      stageStartedAt: Value(stageStartedAt),
      growthProgress: Value(growthProgress),
      growthFactor: Value(growthFactor),
      waterUsed: Value(waterUsed),
      fertilizerUsed: Value(fertilizerUsed),
      status: Value(status),
      plantedAt: Value(plantedAt),
      lastWaterAt: lastWaterAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastWaterAt),
      wiltedAt: wiltedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(wiltedAt),
      deadAt:
          deadAt == null && nullToAbsent ? const Value.absent() : Value(deadAt),
      bloomedAt: bloomedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(bloomedAt),
      mood: Value(mood),
    );
  }

  factory Plant.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Plant(
      id: serializer.fromJson<String>(json['id']),
      speciesId: serializer.fromJson<String>(json['speciesId']),
      potIndex: serializer.fromJson<int>(json['potIndex']),
      stage: serializer.fromJson<int>(json['stage']),
      stageStartedAt: serializer.fromJson<DateTime>(json['stageStartedAt']),
      growthProgress: serializer.fromJson<double>(json['growthProgress']),
      growthFactor: serializer.fromJson<double>(json['growthFactor']),
      waterUsed: serializer.fromJson<bool>(json['waterUsed']),
      fertilizerUsed: serializer.fromJson<bool>(json['fertilizerUsed']),
      status: serializer.fromJson<int>(json['status']),
      plantedAt: serializer.fromJson<DateTime>(json['plantedAt']),
      lastWaterAt: serializer.fromJson<DateTime?>(json['lastWaterAt']),
      wiltedAt: serializer.fromJson<DateTime?>(json['wiltedAt']),
      deadAt: serializer.fromJson<DateTime?>(json['deadAt']),
      bloomedAt: serializer.fromJson<DateTime?>(json['bloomedAt']),
      mood: serializer.fromJson<int>(json['mood']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'speciesId': serializer.toJson<String>(speciesId),
      'potIndex': serializer.toJson<int>(potIndex),
      'stage': serializer.toJson<int>(stage),
      'stageStartedAt': serializer.toJson<DateTime>(stageStartedAt),
      'growthProgress': serializer.toJson<double>(growthProgress),
      'growthFactor': serializer.toJson<double>(growthFactor),
      'waterUsed': serializer.toJson<bool>(waterUsed),
      'fertilizerUsed': serializer.toJson<bool>(fertilizerUsed),
      'status': serializer.toJson<int>(status),
      'plantedAt': serializer.toJson<DateTime>(plantedAt),
      'lastWaterAt': serializer.toJson<DateTime?>(lastWaterAt),
      'wiltedAt': serializer.toJson<DateTime?>(wiltedAt),
      'deadAt': serializer.toJson<DateTime?>(deadAt),
      'bloomedAt': serializer.toJson<DateTime?>(bloomedAt),
      'mood': serializer.toJson<int>(mood),
    };
  }

  Plant copyWith(
          {String? id,
          String? speciesId,
          int? potIndex,
          int? stage,
          DateTime? stageStartedAt,
          double? growthProgress,
          double? growthFactor,
          bool? waterUsed,
          bool? fertilizerUsed,
          int? status,
          DateTime? plantedAt,
          Value<DateTime?> lastWaterAt = const Value.absent(),
          Value<DateTime?> wiltedAt = const Value.absent(),
          Value<DateTime?> deadAt = const Value.absent(),
          Value<DateTime?> bloomedAt = const Value.absent(),
          int? mood}) =>
      Plant(
        id: id ?? this.id,
        speciesId: speciesId ?? this.speciesId,
        potIndex: potIndex ?? this.potIndex,
        stage: stage ?? this.stage,
        stageStartedAt: stageStartedAt ?? this.stageStartedAt,
        growthProgress: growthProgress ?? this.growthProgress,
        growthFactor: growthFactor ?? this.growthFactor,
        waterUsed: waterUsed ?? this.waterUsed,
        fertilizerUsed: fertilizerUsed ?? this.fertilizerUsed,
        status: status ?? this.status,
        plantedAt: plantedAt ?? this.plantedAt,
        lastWaterAt: lastWaterAt.present ? lastWaterAt.value : this.lastWaterAt,
        wiltedAt: wiltedAt.present ? wiltedAt.value : this.wiltedAt,
        deadAt: deadAt.present ? deadAt.value : this.deadAt,
        bloomedAt: bloomedAt.present ? bloomedAt.value : this.bloomedAt,
        mood: mood ?? this.mood,
      );
  Plant copyWithCompanion(PlantsCompanion data) {
    return Plant(
      id: data.id.present ? data.id.value : this.id,
      speciesId: data.speciesId.present ? data.speciesId.value : this.speciesId,
      potIndex: data.potIndex.present ? data.potIndex.value : this.potIndex,
      stage: data.stage.present ? data.stage.value : this.stage,
      stageStartedAt: data.stageStartedAt.present
          ? data.stageStartedAt.value
          : this.stageStartedAt,
      growthProgress: data.growthProgress.present
          ? data.growthProgress.value
          : this.growthProgress,
      growthFactor: data.growthFactor.present
          ? data.growthFactor.value
          : this.growthFactor,
      waterUsed: data.waterUsed.present ? data.waterUsed.value : this.waterUsed,
      fertilizerUsed: data.fertilizerUsed.present
          ? data.fertilizerUsed.value
          : this.fertilizerUsed,
      status: data.status.present ? data.status.value : this.status,
      plantedAt: data.plantedAt.present ? data.plantedAt.value : this.plantedAt,
      lastWaterAt:
          data.lastWaterAt.present ? data.lastWaterAt.value : this.lastWaterAt,
      wiltedAt: data.wiltedAt.present ? data.wiltedAt.value : this.wiltedAt,
      deadAt: data.deadAt.present ? data.deadAt.value : this.deadAt,
      bloomedAt: data.bloomedAt.present ? data.bloomedAt.value : this.bloomedAt,
      mood: data.mood.present ? data.mood.value : this.mood,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Plant(')
          ..write('id: $id, ')
          ..write('speciesId: $speciesId, ')
          ..write('potIndex: $potIndex, ')
          ..write('stage: $stage, ')
          ..write('stageStartedAt: $stageStartedAt, ')
          ..write('growthProgress: $growthProgress, ')
          ..write('growthFactor: $growthFactor, ')
          ..write('waterUsed: $waterUsed, ')
          ..write('fertilizerUsed: $fertilizerUsed, ')
          ..write('status: $status, ')
          ..write('plantedAt: $plantedAt, ')
          ..write('lastWaterAt: $lastWaterAt, ')
          ..write('wiltedAt: $wiltedAt, ')
          ..write('deadAt: $deadAt, ')
          ..write('bloomedAt: $bloomedAt, ')
          ..write('mood: $mood')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      speciesId,
      potIndex,
      stage,
      stageStartedAt,
      growthProgress,
      growthFactor,
      waterUsed,
      fertilizerUsed,
      status,
      plantedAt,
      lastWaterAt,
      wiltedAt,
      deadAt,
      bloomedAt,
      mood);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Plant &&
          other.id == this.id &&
          other.speciesId == this.speciesId &&
          other.potIndex == this.potIndex &&
          other.stage == this.stage &&
          other.stageStartedAt == this.stageStartedAt &&
          other.growthProgress == this.growthProgress &&
          other.growthFactor == this.growthFactor &&
          other.waterUsed == this.waterUsed &&
          other.fertilizerUsed == this.fertilizerUsed &&
          other.status == this.status &&
          other.plantedAt == this.plantedAt &&
          other.lastWaterAt == this.lastWaterAt &&
          other.wiltedAt == this.wiltedAt &&
          other.deadAt == this.deadAt &&
          other.bloomedAt == this.bloomedAt &&
          other.mood == this.mood);
}

class PlantsCompanion extends UpdateCompanion<Plant> {
  final Value<String> id;
  final Value<String> speciesId;
  final Value<int> potIndex;
  final Value<int> stage;
  final Value<DateTime> stageStartedAt;
  final Value<double> growthProgress;
  final Value<double> growthFactor;
  final Value<bool> waterUsed;
  final Value<bool> fertilizerUsed;
  final Value<int> status;
  final Value<DateTime> plantedAt;
  final Value<DateTime?> lastWaterAt;
  final Value<DateTime?> wiltedAt;
  final Value<DateTime?> deadAt;
  final Value<DateTime?> bloomedAt;
  final Value<int> mood;
  final Value<int> rowid;
  const PlantsCompanion({
    this.id = const Value.absent(),
    this.speciesId = const Value.absent(),
    this.potIndex = const Value.absent(),
    this.stage = const Value.absent(),
    this.stageStartedAt = const Value.absent(),
    this.growthProgress = const Value.absent(),
    this.growthFactor = const Value.absent(),
    this.waterUsed = const Value.absent(),
    this.fertilizerUsed = const Value.absent(),
    this.status = const Value.absent(),
    this.plantedAt = const Value.absent(),
    this.lastWaterAt = const Value.absent(),
    this.wiltedAt = const Value.absent(),
    this.deadAt = const Value.absent(),
    this.bloomedAt = const Value.absent(),
    this.mood = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlantsCompanion.insert({
    required String id,
    required String speciesId,
    required int potIndex,
    required int stage,
    required DateTime stageStartedAt,
    this.growthProgress = const Value.absent(),
    this.growthFactor = const Value.absent(),
    this.waterUsed = const Value.absent(),
    this.fertilizerUsed = const Value.absent(),
    required int status,
    required DateTime plantedAt,
    this.lastWaterAt = const Value.absent(),
    this.wiltedAt = const Value.absent(),
    this.deadAt = const Value.absent(),
    this.bloomedAt = const Value.absent(),
    this.mood = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        speciesId = Value(speciesId),
        potIndex = Value(potIndex),
        stage = Value(stage),
        stageStartedAt = Value(stageStartedAt),
        status = Value(status),
        plantedAt = Value(plantedAt);
  static Insertable<Plant> custom({
    Expression<String>? id,
    Expression<String>? speciesId,
    Expression<int>? potIndex,
    Expression<int>? stage,
    Expression<DateTime>? stageStartedAt,
    Expression<double>? growthProgress,
    Expression<double>? growthFactor,
    Expression<bool>? waterUsed,
    Expression<bool>? fertilizerUsed,
    Expression<int>? status,
    Expression<DateTime>? plantedAt,
    Expression<DateTime>? lastWaterAt,
    Expression<DateTime>? wiltedAt,
    Expression<DateTime>? deadAt,
    Expression<DateTime>? bloomedAt,
    Expression<int>? mood,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (speciesId != null) 'species_id': speciesId,
      if (potIndex != null) 'pot_index': potIndex,
      if (stage != null) 'stage': stage,
      if (stageStartedAt != null) 'stage_started_at': stageStartedAt,
      if (growthProgress != null) 'growth_progress': growthProgress,
      if (growthFactor != null) 'growth_factor': growthFactor,
      if (waterUsed != null) 'water_used': waterUsed,
      if (fertilizerUsed != null) 'fertilizer_used': fertilizerUsed,
      if (status != null) 'status': status,
      if (plantedAt != null) 'planted_at': plantedAt,
      if (lastWaterAt != null) 'last_water_at': lastWaterAt,
      if (wiltedAt != null) 'wilted_at': wiltedAt,
      if (deadAt != null) 'dead_at': deadAt,
      if (bloomedAt != null) 'bloomed_at': bloomedAt,
      if (mood != null) 'mood': mood,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlantsCompanion copyWith(
      {Value<String>? id,
      Value<String>? speciesId,
      Value<int>? potIndex,
      Value<int>? stage,
      Value<DateTime>? stageStartedAt,
      Value<double>? growthProgress,
      Value<double>? growthFactor,
      Value<bool>? waterUsed,
      Value<bool>? fertilizerUsed,
      Value<int>? status,
      Value<DateTime>? plantedAt,
      Value<DateTime?>? lastWaterAt,
      Value<DateTime?>? wiltedAt,
      Value<DateTime?>? deadAt,
      Value<DateTime?>? bloomedAt,
      Value<int>? mood,
      Value<int>? rowid}) {
    return PlantsCompanion(
      id: id ?? this.id,
      speciesId: speciesId ?? this.speciesId,
      potIndex: potIndex ?? this.potIndex,
      stage: stage ?? this.stage,
      stageStartedAt: stageStartedAt ?? this.stageStartedAt,
      growthProgress: growthProgress ?? this.growthProgress,
      growthFactor: growthFactor ?? this.growthFactor,
      waterUsed: waterUsed ?? this.waterUsed,
      fertilizerUsed: fertilizerUsed ?? this.fertilizerUsed,
      status: status ?? this.status,
      plantedAt: plantedAt ?? this.plantedAt,
      lastWaterAt: lastWaterAt ?? this.lastWaterAt,
      wiltedAt: wiltedAt ?? this.wiltedAt,
      deadAt: deadAt ?? this.deadAt,
      bloomedAt: bloomedAt ?? this.bloomedAt,
      mood: mood ?? this.mood,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (speciesId.present) {
      map['species_id'] = Variable<String>(speciesId.value);
    }
    if (potIndex.present) {
      map['pot_index'] = Variable<int>(potIndex.value);
    }
    if (stage.present) {
      map['stage'] = Variable<int>(stage.value);
    }
    if (stageStartedAt.present) {
      map['stage_started_at'] = Variable<DateTime>(stageStartedAt.value);
    }
    if (growthProgress.present) {
      map['growth_progress'] = Variable<double>(growthProgress.value);
    }
    if (growthFactor.present) {
      map['growth_factor'] = Variable<double>(growthFactor.value);
    }
    if (waterUsed.present) {
      map['water_used'] = Variable<bool>(waterUsed.value);
    }
    if (fertilizerUsed.present) {
      map['fertilizer_used'] = Variable<bool>(fertilizerUsed.value);
    }
    if (status.present) {
      map['status'] = Variable<int>(status.value);
    }
    if (plantedAt.present) {
      map['planted_at'] = Variable<DateTime>(plantedAt.value);
    }
    if (lastWaterAt.present) {
      map['last_water_at'] = Variable<DateTime>(lastWaterAt.value);
    }
    if (wiltedAt.present) {
      map['wilted_at'] = Variable<DateTime>(wiltedAt.value);
    }
    if (deadAt.present) {
      map['dead_at'] = Variable<DateTime>(deadAt.value);
    }
    if (bloomedAt.present) {
      map['bloomed_at'] = Variable<DateTime>(bloomedAt.value);
    }
    if (mood.present) {
      map['mood'] = Variable<int>(mood.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlantsCompanion(')
          ..write('id: $id, ')
          ..write('speciesId: $speciesId, ')
          ..write('potIndex: $potIndex, ')
          ..write('stage: $stage, ')
          ..write('stageStartedAt: $stageStartedAt, ')
          ..write('growthProgress: $growthProgress, ')
          ..write('growthFactor: $growthFactor, ')
          ..write('waterUsed: $waterUsed, ')
          ..write('fertilizerUsed: $fertilizerUsed, ')
          ..write('status: $status, ')
          ..write('plantedAt: $plantedAt, ')
          ..write('lastWaterAt: $lastWaterAt, ')
          ..write('wiltedAt: $wiltedAt, ')
          ..write('deadAt: $deadAt, ')
          ..write('bloomedAt: $bloomedAt, ')
          ..write('mood: $mood, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FocusSessionsTable extends FocusSessions
    with TableInfo<$FocusSessionsTable, FocusSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FocusSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _startMeta = const VerificationMeta('start');
  @override
  late final GeneratedColumn<DateTime> start = GeneratedColumn<DateTime>(
      'start', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _endMeta = const VerificationMeta('end');
  @override
  late final GeneratedColumn<DateTime> end = GeneratedColumn<DateTime>(
      'end', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _plannedMinMeta =
      const VerificationMeta('plannedMin');
  @override
  late final GeneratedColumn<int> plannedMin = GeneratedColumn<int>(
      'planned_min', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _actualFocusMinMeta =
      const VerificationMeta('actualFocusMin');
  @override
  late final GeneratedColumn<double> actualFocusMin = GeneratedColumn<double>(
      'actual_focus_min', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<int> status = GeneratedColumn<int>(
      'status', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _sunlightEarnedMeta =
      const VerificationMeta('sunlightEarned');
  @override
  late final GeneratedColumn<double> sunlightEarned = GeneratedColumn<double>(
      'sunlight_earned', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        start,
        end,
        plannedMin,
        actualFocusMin,
        status,
        sunlightEarned,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'focus_sessions';
  @override
  VerificationContext validateIntegrity(Insertable<FocusSession> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('start')) {
      context.handle(
          _startMeta, start.isAcceptableOrUnknown(data['start']!, _startMeta));
    } else if (isInserting) {
      context.missing(_startMeta);
    }
    if (data.containsKey('end')) {
      context.handle(
          _endMeta, end.isAcceptableOrUnknown(data['end']!, _endMeta));
    }
    if (data.containsKey('planned_min')) {
      context.handle(
          _plannedMinMeta,
          plannedMin.isAcceptableOrUnknown(
              data['planned_min']!, _plannedMinMeta));
    } else if (isInserting) {
      context.missing(_plannedMinMeta);
    }
    if (data.containsKey('actual_focus_min')) {
      context.handle(
          _actualFocusMinMeta,
          actualFocusMin.isAcceptableOrUnknown(
              data['actual_focus_min']!, _actualFocusMinMeta));
    } else if (isInserting) {
      context.missing(_actualFocusMinMeta);
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('sunlight_earned')) {
      context.handle(
          _sunlightEarnedMeta,
          sunlightEarned.isAcceptableOrUnknown(
              data['sunlight_earned']!, _sunlightEarnedMeta));
    } else if (isInserting) {
      context.missing(_sunlightEarnedMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FocusSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FocusSession(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      start: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}start'])!,
      end: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}end']),
      plannedMin: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}planned_min'])!,
      actualFocusMin: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}actual_focus_min'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}status'])!,
      sunlightEarned: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}sunlight_earned'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $FocusSessionsTable createAlias(String alias) {
    return $FocusSessionsTable(attachedDatabase, alias);
  }
}

class FocusSession extends DataClass implements Insertable<FocusSession> {
  final String id;
  final DateTime start;
  final DateTime? end;
  final int plannedMin;
  final double actualFocusMin;
  final int status;
  final double sunlightEarned;
  final DateTime createdAt;
  const FocusSession(
      {required this.id,
      required this.start,
      this.end,
      required this.plannedMin,
      required this.actualFocusMin,
      required this.status,
      required this.sunlightEarned,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['start'] = Variable<DateTime>(start);
    if (!nullToAbsent || end != null) {
      map['end'] = Variable<DateTime>(end);
    }
    map['planned_min'] = Variable<int>(plannedMin);
    map['actual_focus_min'] = Variable<double>(actualFocusMin);
    map['status'] = Variable<int>(status);
    map['sunlight_earned'] = Variable<double>(sunlightEarned);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  FocusSessionsCompanion toCompanion(bool nullToAbsent) {
    return FocusSessionsCompanion(
      id: Value(id),
      start: Value(start),
      end: end == null && nullToAbsent ? const Value.absent() : Value(end),
      plannedMin: Value(plannedMin),
      actualFocusMin: Value(actualFocusMin),
      status: Value(status),
      sunlightEarned: Value(sunlightEarned),
      createdAt: Value(createdAt),
    );
  }

  factory FocusSession.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FocusSession(
      id: serializer.fromJson<String>(json['id']),
      start: serializer.fromJson<DateTime>(json['start']),
      end: serializer.fromJson<DateTime?>(json['end']),
      plannedMin: serializer.fromJson<int>(json['plannedMin']),
      actualFocusMin: serializer.fromJson<double>(json['actualFocusMin']),
      status: serializer.fromJson<int>(json['status']),
      sunlightEarned: serializer.fromJson<double>(json['sunlightEarned']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'start': serializer.toJson<DateTime>(start),
      'end': serializer.toJson<DateTime?>(end),
      'plannedMin': serializer.toJson<int>(plannedMin),
      'actualFocusMin': serializer.toJson<double>(actualFocusMin),
      'status': serializer.toJson<int>(status),
      'sunlightEarned': serializer.toJson<double>(sunlightEarned),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  FocusSession copyWith(
          {String? id,
          DateTime? start,
          Value<DateTime?> end = const Value.absent(),
          int? plannedMin,
          double? actualFocusMin,
          int? status,
          double? sunlightEarned,
          DateTime? createdAt}) =>
      FocusSession(
        id: id ?? this.id,
        start: start ?? this.start,
        end: end.present ? end.value : this.end,
        plannedMin: plannedMin ?? this.plannedMin,
        actualFocusMin: actualFocusMin ?? this.actualFocusMin,
        status: status ?? this.status,
        sunlightEarned: sunlightEarned ?? this.sunlightEarned,
        createdAt: createdAt ?? this.createdAt,
      );
  FocusSession copyWithCompanion(FocusSessionsCompanion data) {
    return FocusSession(
      id: data.id.present ? data.id.value : this.id,
      start: data.start.present ? data.start.value : this.start,
      end: data.end.present ? data.end.value : this.end,
      plannedMin:
          data.plannedMin.present ? data.plannedMin.value : this.plannedMin,
      actualFocusMin: data.actualFocusMin.present
          ? data.actualFocusMin.value
          : this.actualFocusMin,
      status: data.status.present ? data.status.value : this.status,
      sunlightEarned: data.sunlightEarned.present
          ? data.sunlightEarned.value
          : this.sunlightEarned,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FocusSession(')
          ..write('id: $id, ')
          ..write('start: $start, ')
          ..write('end: $end, ')
          ..write('plannedMin: $plannedMin, ')
          ..write('actualFocusMin: $actualFocusMin, ')
          ..write('status: $status, ')
          ..write('sunlightEarned: $sunlightEarned, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, start, end, plannedMin, actualFocusMin,
      status, sunlightEarned, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FocusSession &&
          other.id == this.id &&
          other.start == this.start &&
          other.end == this.end &&
          other.plannedMin == this.plannedMin &&
          other.actualFocusMin == this.actualFocusMin &&
          other.status == this.status &&
          other.sunlightEarned == this.sunlightEarned &&
          other.createdAt == this.createdAt);
}

class FocusSessionsCompanion extends UpdateCompanion<FocusSession> {
  final Value<String> id;
  final Value<DateTime> start;
  final Value<DateTime?> end;
  final Value<int> plannedMin;
  final Value<double> actualFocusMin;
  final Value<int> status;
  final Value<double> sunlightEarned;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const FocusSessionsCompanion({
    this.id = const Value.absent(),
    this.start = const Value.absent(),
    this.end = const Value.absent(),
    this.plannedMin = const Value.absent(),
    this.actualFocusMin = const Value.absent(),
    this.status = const Value.absent(),
    this.sunlightEarned = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FocusSessionsCompanion.insert({
    required String id,
    required DateTime start,
    this.end = const Value.absent(),
    required int plannedMin,
    required double actualFocusMin,
    required int status,
    required double sunlightEarned,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        start = Value(start),
        plannedMin = Value(plannedMin),
        actualFocusMin = Value(actualFocusMin),
        status = Value(status),
        sunlightEarned = Value(sunlightEarned),
        createdAt = Value(createdAt);
  static Insertable<FocusSession> custom({
    Expression<String>? id,
    Expression<DateTime>? start,
    Expression<DateTime>? end,
    Expression<int>? plannedMin,
    Expression<double>? actualFocusMin,
    Expression<int>? status,
    Expression<double>? sunlightEarned,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (start != null) 'start': start,
      if (end != null) 'end': end,
      if (plannedMin != null) 'planned_min': plannedMin,
      if (actualFocusMin != null) 'actual_focus_min': actualFocusMin,
      if (status != null) 'status': status,
      if (sunlightEarned != null) 'sunlight_earned': sunlightEarned,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FocusSessionsCompanion copyWith(
      {Value<String>? id,
      Value<DateTime>? start,
      Value<DateTime?>? end,
      Value<int>? plannedMin,
      Value<double>? actualFocusMin,
      Value<int>? status,
      Value<double>? sunlightEarned,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return FocusSessionsCompanion(
      id: id ?? this.id,
      start: start ?? this.start,
      end: end ?? this.end,
      plannedMin: plannedMin ?? this.plannedMin,
      actualFocusMin: actualFocusMin ?? this.actualFocusMin,
      status: status ?? this.status,
      sunlightEarned: sunlightEarned ?? this.sunlightEarned,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (start.present) {
      map['start'] = Variable<DateTime>(start.value);
    }
    if (end.present) {
      map['end'] = Variable<DateTime>(end.value);
    }
    if (plannedMin.present) {
      map['planned_min'] = Variable<int>(plannedMin.value);
    }
    if (actualFocusMin.present) {
      map['actual_focus_min'] = Variable<double>(actualFocusMin.value);
    }
    if (status.present) {
      map['status'] = Variable<int>(status.value);
    }
    if (sunlightEarned.present) {
      map['sunlight_earned'] = Variable<double>(sunlightEarned.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FocusSessionsCompanion(')
          ..write('id: $id, ')
          ..write('start: $start, ')
          ..write('end: $end, ')
          ..write('plannedMin: $plannedMin, ')
          ..write('actualFocusMin: $actualFocusMin, ')
          ..write('status: $status, ')
          ..write('sunlightEarned: $sunlightEarned, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SunlightLedgersTable extends SunlightLedgers
    with TableInfo<$SunlightLedgersTable, SunlightLedger> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SunlightLedgersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _tsMeta = const VerificationMeta('ts');
  @override
  late final GeneratedColumn<DateTime> ts = GeneratedColumn<DateTime>(
      'ts', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<int> type = GeneratedColumn<int>(
      'type', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _grossMeta = const VerificationMeta('gross');
  @override
  late final GeneratedColumn<double> gross = GeneratedColumn<double>(
      'gross', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _netMeta = const VerificationMeta('net');
  @override
  late final GeneratedColumn<double> net = GeneratedColumn<double>(
      'net', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _balanceAfterMeta =
      const VerificationMeta('balanceAfter');
  @override
  late final GeneratedColumn<double> balanceAfter = GeneratedColumn<double>(
      'balance_after', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _refTypeMeta =
      const VerificationMeta('refType');
  @override
  late final GeneratedColumn<String> refType = GeneratedColumn<String>(
      'ref_type', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _refIdMeta = const VerificationMeta('refId');
  @override
  late final GeneratedColumn<String> refId = GeneratedColumn<String>(
      'ref_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _dayKeyMeta = const VerificationMeta('dayKey');
  @override
  late final GeneratedColumn<String> dayKey = GeneratedColumn<String>(
      'day_key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, ts, type, gross, net, balanceAfter, refType, refId, dayKey];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sunlight_ledgers';
  @override
  VerificationContext validateIntegrity(Insertable<SunlightLedger> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('ts')) {
      context.handle(_tsMeta, ts.isAcceptableOrUnknown(data['ts']!, _tsMeta));
    } else if (isInserting) {
      context.missing(_tsMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('gross')) {
      context.handle(
          _grossMeta, gross.isAcceptableOrUnknown(data['gross']!, _grossMeta));
    } else if (isInserting) {
      context.missing(_grossMeta);
    }
    if (data.containsKey('net')) {
      context.handle(
          _netMeta, net.isAcceptableOrUnknown(data['net']!, _netMeta));
    } else if (isInserting) {
      context.missing(_netMeta);
    }
    if (data.containsKey('balance_after')) {
      context.handle(
          _balanceAfterMeta,
          balanceAfter.isAcceptableOrUnknown(
              data['balance_after']!, _balanceAfterMeta));
    } else if (isInserting) {
      context.missing(_balanceAfterMeta);
    }
    if (data.containsKey('ref_type')) {
      context.handle(_refTypeMeta,
          refType.isAcceptableOrUnknown(data['ref_type']!, _refTypeMeta));
    }
    if (data.containsKey('ref_id')) {
      context.handle(
          _refIdMeta, refId.isAcceptableOrUnknown(data['ref_id']!, _refIdMeta));
    }
    if (data.containsKey('day_key')) {
      context.handle(_dayKeyMeta,
          dayKey.isAcceptableOrUnknown(data['day_key']!, _dayKeyMeta));
    } else if (isInserting) {
      context.missing(_dayKeyMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SunlightLedger map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SunlightLedger(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      ts: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}ts'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}type'])!,
      gross: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}gross'])!,
      net: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}net'])!,
      balanceAfter: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}balance_after'])!,
      refType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}ref_type']),
      refId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}ref_id']),
      dayKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}day_key'])!,
    );
  }

  @override
  $SunlightLedgersTable createAlias(String alias) {
    return $SunlightLedgersTable(attachedDatabase, alias);
  }
}

class SunlightLedger extends DataClass implements Insertable<SunlightLedger> {
  final String id;
  final DateTime ts;
  final int type;
  final double gross;
  final double net;
  final double balanceAfter;
  final String? refType;
  final String? refId;
  final String dayKey;
  const SunlightLedger(
      {required this.id,
      required this.ts,
      required this.type,
      required this.gross,
      required this.net,
      required this.balanceAfter,
      this.refType,
      this.refId,
      required this.dayKey});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['ts'] = Variable<DateTime>(ts);
    map['type'] = Variable<int>(type);
    map['gross'] = Variable<double>(gross);
    map['net'] = Variable<double>(net);
    map['balance_after'] = Variable<double>(balanceAfter);
    if (!nullToAbsent || refType != null) {
      map['ref_type'] = Variable<String>(refType);
    }
    if (!nullToAbsent || refId != null) {
      map['ref_id'] = Variable<String>(refId);
    }
    map['day_key'] = Variable<String>(dayKey);
    return map;
  }

  SunlightLedgersCompanion toCompanion(bool nullToAbsent) {
    return SunlightLedgersCompanion(
      id: Value(id),
      ts: Value(ts),
      type: Value(type),
      gross: Value(gross),
      net: Value(net),
      balanceAfter: Value(balanceAfter),
      refType: refType == null && nullToAbsent
          ? const Value.absent()
          : Value(refType),
      refId:
          refId == null && nullToAbsent ? const Value.absent() : Value(refId),
      dayKey: Value(dayKey),
    );
  }

  factory SunlightLedger.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SunlightLedger(
      id: serializer.fromJson<String>(json['id']),
      ts: serializer.fromJson<DateTime>(json['ts']),
      type: serializer.fromJson<int>(json['type']),
      gross: serializer.fromJson<double>(json['gross']),
      net: serializer.fromJson<double>(json['net']),
      balanceAfter: serializer.fromJson<double>(json['balanceAfter']),
      refType: serializer.fromJson<String?>(json['refType']),
      refId: serializer.fromJson<String?>(json['refId']),
      dayKey: serializer.fromJson<String>(json['dayKey']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'ts': serializer.toJson<DateTime>(ts),
      'type': serializer.toJson<int>(type),
      'gross': serializer.toJson<double>(gross),
      'net': serializer.toJson<double>(net),
      'balanceAfter': serializer.toJson<double>(balanceAfter),
      'refType': serializer.toJson<String?>(refType),
      'refId': serializer.toJson<String?>(refId),
      'dayKey': serializer.toJson<String>(dayKey),
    };
  }

  SunlightLedger copyWith(
          {String? id,
          DateTime? ts,
          int? type,
          double? gross,
          double? net,
          double? balanceAfter,
          Value<String?> refType = const Value.absent(),
          Value<String?> refId = const Value.absent(),
          String? dayKey}) =>
      SunlightLedger(
        id: id ?? this.id,
        ts: ts ?? this.ts,
        type: type ?? this.type,
        gross: gross ?? this.gross,
        net: net ?? this.net,
        balanceAfter: balanceAfter ?? this.balanceAfter,
        refType: refType.present ? refType.value : this.refType,
        refId: refId.present ? refId.value : this.refId,
        dayKey: dayKey ?? this.dayKey,
      );
  SunlightLedger copyWithCompanion(SunlightLedgersCompanion data) {
    return SunlightLedger(
      id: data.id.present ? data.id.value : this.id,
      ts: data.ts.present ? data.ts.value : this.ts,
      type: data.type.present ? data.type.value : this.type,
      gross: data.gross.present ? data.gross.value : this.gross,
      net: data.net.present ? data.net.value : this.net,
      balanceAfter: data.balanceAfter.present
          ? data.balanceAfter.value
          : this.balanceAfter,
      refType: data.refType.present ? data.refType.value : this.refType,
      refId: data.refId.present ? data.refId.value : this.refId,
      dayKey: data.dayKey.present ? data.dayKey.value : this.dayKey,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SunlightLedger(')
          ..write('id: $id, ')
          ..write('ts: $ts, ')
          ..write('type: $type, ')
          ..write('gross: $gross, ')
          ..write('net: $net, ')
          ..write('balanceAfter: $balanceAfter, ')
          ..write('refType: $refType, ')
          ..write('refId: $refId, ')
          ..write('dayKey: $dayKey')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, ts, type, gross, net, balanceAfter, refType, refId, dayKey);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SunlightLedger &&
          other.id == this.id &&
          other.ts == this.ts &&
          other.type == this.type &&
          other.gross == this.gross &&
          other.net == this.net &&
          other.balanceAfter == this.balanceAfter &&
          other.refType == this.refType &&
          other.refId == this.refId &&
          other.dayKey == this.dayKey);
}

class SunlightLedgersCompanion extends UpdateCompanion<SunlightLedger> {
  final Value<String> id;
  final Value<DateTime> ts;
  final Value<int> type;
  final Value<double> gross;
  final Value<double> net;
  final Value<double> balanceAfter;
  final Value<String?> refType;
  final Value<String?> refId;
  final Value<String> dayKey;
  final Value<int> rowid;
  const SunlightLedgersCompanion({
    this.id = const Value.absent(),
    this.ts = const Value.absent(),
    this.type = const Value.absent(),
    this.gross = const Value.absent(),
    this.net = const Value.absent(),
    this.balanceAfter = const Value.absent(),
    this.refType = const Value.absent(),
    this.refId = const Value.absent(),
    this.dayKey = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SunlightLedgersCompanion.insert({
    required String id,
    required DateTime ts,
    required int type,
    required double gross,
    required double net,
    required double balanceAfter,
    this.refType = const Value.absent(),
    this.refId = const Value.absent(),
    required String dayKey,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        ts = Value(ts),
        type = Value(type),
        gross = Value(gross),
        net = Value(net),
        balanceAfter = Value(balanceAfter),
        dayKey = Value(dayKey);
  static Insertable<SunlightLedger> custom({
    Expression<String>? id,
    Expression<DateTime>? ts,
    Expression<int>? type,
    Expression<double>? gross,
    Expression<double>? net,
    Expression<double>? balanceAfter,
    Expression<String>? refType,
    Expression<String>? refId,
    Expression<String>? dayKey,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ts != null) 'ts': ts,
      if (type != null) 'type': type,
      if (gross != null) 'gross': gross,
      if (net != null) 'net': net,
      if (balanceAfter != null) 'balance_after': balanceAfter,
      if (refType != null) 'ref_type': refType,
      if (refId != null) 'ref_id': refId,
      if (dayKey != null) 'day_key': dayKey,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SunlightLedgersCompanion copyWith(
      {Value<String>? id,
      Value<DateTime>? ts,
      Value<int>? type,
      Value<double>? gross,
      Value<double>? net,
      Value<double>? balanceAfter,
      Value<String?>? refType,
      Value<String?>? refId,
      Value<String>? dayKey,
      Value<int>? rowid}) {
    return SunlightLedgersCompanion(
      id: id ?? this.id,
      ts: ts ?? this.ts,
      type: type ?? this.type,
      gross: gross ?? this.gross,
      net: net ?? this.net,
      balanceAfter: balanceAfter ?? this.balanceAfter,
      refType: refType ?? this.refType,
      refId: refId ?? this.refId,
      dayKey: dayKey ?? this.dayKey,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (ts.present) {
      map['ts'] = Variable<DateTime>(ts.value);
    }
    if (type.present) {
      map['type'] = Variable<int>(type.value);
    }
    if (gross.present) {
      map['gross'] = Variable<double>(gross.value);
    }
    if (net.present) {
      map['net'] = Variable<double>(net.value);
    }
    if (balanceAfter.present) {
      map['balance_after'] = Variable<double>(balanceAfter.value);
    }
    if (refType.present) {
      map['ref_type'] = Variable<String>(refType.value);
    }
    if (refId.present) {
      map['ref_id'] = Variable<String>(refId.value);
    }
    if (dayKey.present) {
      map['day_key'] = Variable<String>(dayKey.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SunlightLedgersCompanion(')
          ..write('id: $id, ')
          ..write('ts: $ts, ')
          ..write('type: $type, ')
          ..write('gross: $gross, ')
          ..write('net: $net, ')
          ..write('balanceAfter: $balanceAfter, ')
          ..write('refType: $refType, ')
          ..write('refId: $refId, ')
          ..write('dayKey: $dayKey, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RewardTemplatesTable extends RewardTemplates
    with TableInfo<$RewardTemplatesTable, RewardTemplate> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RewardTemplatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _categoryMeta =
      const VerificationMeta('category');
  @override
  late final GeneratedColumn<int> category = GeneratedColumn<int>(
      'category', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _baseCostMeta =
      const VerificationMeta('baseCost');
  @override
  late final GeneratedColumn<int> baseCost = GeneratedColumn<int>(
      'base_cost', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(50));
  static const VerificationMeta _freqLimitMeta =
      const VerificationMeta('freqLimit');
  @override
  late final GeneratedColumn<int> freqLimit = GeneratedColumn<int>(
      'freq_limit', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _cooldownRuleMeta =
      const VerificationMeta('cooldownRule');
  @override
  late final GeneratedColumn<int> cooldownRule = GeneratedColumn<int>(
      'cooldown_rule', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  static const VerificationMeta _enabledMeta =
      const VerificationMeta('enabled');
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
      'enabled', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("enabled" IN (0, 1))'),
      defaultValue: const Constant(true));
  @override
  List<GeneratedColumn> get $columns =>
      [id, name, category, baseCost, freqLimit, cooldownRule, enabled];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'reward_templates';
  @override
  VerificationContext validateIntegrity(Insertable<RewardTemplate> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('category')) {
      context.handle(_categoryMeta,
          category.isAcceptableOrUnknown(data['category']!, _categoryMeta));
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('base_cost')) {
      context.handle(_baseCostMeta,
          baseCost.isAcceptableOrUnknown(data['base_cost']!, _baseCostMeta));
    }
    if (data.containsKey('freq_limit')) {
      context.handle(_freqLimitMeta,
          freqLimit.isAcceptableOrUnknown(data['freq_limit']!, _freqLimitMeta));
    }
    if (data.containsKey('cooldown_rule')) {
      context.handle(
          _cooldownRuleMeta,
          cooldownRule.isAcceptableOrUnknown(
              data['cooldown_rule']!, _cooldownRuleMeta));
    }
    if (data.containsKey('enabled')) {
      context.handle(_enabledMeta,
          enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RewardTemplate map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RewardTemplate(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      category: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}category'])!,
      baseCost: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}base_cost'])!,
      freqLimit: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}freq_limit']),
      cooldownRule: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}cooldown_rule'])!,
      enabled: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}enabled'])!,
    );
  }

  @override
  $RewardTemplatesTable createAlias(String alias) {
    return $RewardTemplatesTable(attachedDatabase, alias);
  }
}

class RewardTemplate extends DataClass implements Insertable<RewardTemplate> {
  final String id;
  final String name;
  final int category;
  final int baseCost;
  final int? freqLimit;
  final int cooldownRule;
  final bool enabled;
  const RewardTemplate(
      {required this.id,
      required this.name,
      required this.category,
      required this.baseCost,
      this.freqLimit,
      required this.cooldownRule,
      required this.enabled});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['category'] = Variable<int>(category);
    map['base_cost'] = Variable<int>(baseCost);
    if (!nullToAbsent || freqLimit != null) {
      map['freq_limit'] = Variable<int>(freqLimit);
    }
    map['cooldown_rule'] = Variable<int>(cooldownRule);
    map['enabled'] = Variable<bool>(enabled);
    return map;
  }

  RewardTemplatesCompanion toCompanion(bool nullToAbsent) {
    return RewardTemplatesCompanion(
      id: Value(id),
      name: Value(name),
      category: Value(category),
      baseCost: Value(baseCost),
      freqLimit: freqLimit == null && nullToAbsent
          ? const Value.absent()
          : Value(freqLimit),
      cooldownRule: Value(cooldownRule),
      enabled: Value(enabled),
    );
  }

  factory RewardTemplate.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RewardTemplate(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      category: serializer.fromJson<int>(json['category']),
      baseCost: serializer.fromJson<int>(json['baseCost']),
      freqLimit: serializer.fromJson<int?>(json['freqLimit']),
      cooldownRule: serializer.fromJson<int>(json['cooldownRule']),
      enabled: serializer.fromJson<bool>(json['enabled']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'category': serializer.toJson<int>(category),
      'baseCost': serializer.toJson<int>(baseCost),
      'freqLimit': serializer.toJson<int?>(freqLimit),
      'cooldownRule': serializer.toJson<int>(cooldownRule),
      'enabled': serializer.toJson<bool>(enabled),
    };
  }

  RewardTemplate copyWith(
          {String? id,
          String? name,
          int? category,
          int? baseCost,
          Value<int?> freqLimit = const Value.absent(),
          int? cooldownRule,
          bool? enabled}) =>
      RewardTemplate(
        id: id ?? this.id,
        name: name ?? this.name,
        category: category ?? this.category,
        baseCost: baseCost ?? this.baseCost,
        freqLimit: freqLimit.present ? freqLimit.value : this.freqLimit,
        cooldownRule: cooldownRule ?? this.cooldownRule,
        enabled: enabled ?? this.enabled,
      );
  RewardTemplate copyWithCompanion(RewardTemplatesCompanion data) {
    return RewardTemplate(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      category: data.category.present ? data.category.value : this.category,
      baseCost: data.baseCost.present ? data.baseCost.value : this.baseCost,
      freqLimit: data.freqLimit.present ? data.freqLimit.value : this.freqLimit,
      cooldownRule: data.cooldownRule.present
          ? data.cooldownRule.value
          : this.cooldownRule,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RewardTemplate(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('category: $category, ')
          ..write('baseCost: $baseCost, ')
          ..write('freqLimit: $freqLimit, ')
          ..write('cooldownRule: $cooldownRule, ')
          ..write('enabled: $enabled')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, name, category, baseCost, freqLimit, cooldownRule, enabled);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RewardTemplate &&
          other.id == this.id &&
          other.name == this.name &&
          other.category == this.category &&
          other.baseCost == this.baseCost &&
          other.freqLimit == this.freqLimit &&
          other.cooldownRule == this.cooldownRule &&
          other.enabled == this.enabled);
}

class RewardTemplatesCompanion extends UpdateCompanion<RewardTemplate> {
  final Value<String> id;
  final Value<String> name;
  final Value<int> category;
  final Value<int> baseCost;
  final Value<int?> freqLimit;
  final Value<int> cooldownRule;
  final Value<bool> enabled;
  final Value<int> rowid;
  const RewardTemplatesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.category = const Value.absent(),
    this.baseCost = const Value.absent(),
    this.freqLimit = const Value.absent(),
    this.cooldownRule = const Value.absent(),
    this.enabled = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RewardTemplatesCompanion.insert({
    required String id,
    required String name,
    required int category,
    this.baseCost = const Value.absent(),
    this.freqLimit = const Value.absent(),
    this.cooldownRule = const Value.absent(),
    this.enabled = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        category = Value(category);
  static Insertable<RewardTemplate> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? category,
    Expression<int>? baseCost,
    Expression<int>? freqLimit,
    Expression<int>? cooldownRule,
    Expression<bool>? enabled,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (category != null) 'category': category,
      if (baseCost != null) 'base_cost': baseCost,
      if (freqLimit != null) 'freq_limit': freqLimit,
      if (cooldownRule != null) 'cooldown_rule': cooldownRule,
      if (enabled != null) 'enabled': enabled,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RewardTemplatesCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<int>? category,
      Value<int>? baseCost,
      Value<int?>? freqLimit,
      Value<int>? cooldownRule,
      Value<bool>? enabled,
      Value<int>? rowid}) {
    return RewardTemplatesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      baseCost: baseCost ?? this.baseCost,
      freqLimit: freqLimit ?? this.freqLimit,
      cooldownRule: cooldownRule ?? this.cooldownRule,
      enabled: enabled ?? this.enabled,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (category.present) {
      map['category'] = Variable<int>(category.value);
    }
    if (baseCost.present) {
      map['base_cost'] = Variable<int>(baseCost.value);
    }
    if (freqLimit.present) {
      map['freq_limit'] = Variable<int>(freqLimit.value);
    }
    if (cooldownRule.present) {
      map['cooldown_rule'] = Variable<int>(cooldownRule.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RewardTemplatesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('category: $category, ')
          ..write('baseCost: $baseCost, ')
          ..write('freqLimit: $freqLimit, ')
          ..write('cooldownRule: $cooldownRule, ')
          ..write('enabled: $enabled, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RedemptionRequestsTable extends RedemptionRequests
    with TableInfo<$RedemptionRequestsTable, RedemptionRequest> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RedemptionRequestsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _templateIdMeta =
      const VerificationMeta('templateId');
  @override
  late final GeneratedColumn<String> templateId = GeneratedColumn<String>(
      'template_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _requestedAtMeta =
      const VerificationMeta('requestedAt');
  @override
  late final GeneratedColumn<DateTime> requestedAt = GeneratedColumn<DateTime>(
      'requested_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _costMeta = const VerificationMeta('cost');
  @override
  late final GeneratedColumn<int> cost = GeneratedColumn<int>(
      'cost', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<int> status = GeneratedColumn<int>(
      'status', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _autoApprovedMeta =
      const VerificationMeta('autoApproved');
  @override
  late final GeneratedColumn<bool> autoApproved = GeneratedColumn<bool>(
      'auto_approved', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("auto_approved" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _queuePositionMeta =
      const VerificationMeta('queuePosition');
  @override
  late final GeneratedColumn<int> queuePosition = GeneratedColumn<int>(
      'queue_position', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _verifiedAtMeta =
      const VerificationMeta('verifiedAt');
  @override
  late final GeneratedColumn<DateTime> verifiedAt = GeneratedColumn<DateTime>(
      'verified_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _parentNoteMeta =
      const VerificationMeta('parentNote');
  @override
  late final GeneratedColumn<String> parentNote = GeneratedColumn<String>(
      'parent_note', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _childIdMeta =
      const VerificationMeta('childId');
  @override
  late final GeneratedColumn<String> childId = GeneratedColumn<String>(
      'child_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(kChildIdDefault));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        templateId,
        requestedAt,
        cost,
        status,
        autoApproved,
        queuePosition,
        verifiedAt,
        parentNote,
        childId
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'redemption_requests';
  @override
  VerificationContext validateIntegrity(Insertable<RedemptionRequest> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('template_id')) {
      context.handle(
          _templateIdMeta,
          templateId.isAcceptableOrUnknown(
              data['template_id']!, _templateIdMeta));
    } else if (isInserting) {
      context.missing(_templateIdMeta);
    }
    if (data.containsKey('requested_at')) {
      context.handle(
          _requestedAtMeta,
          requestedAt.isAcceptableOrUnknown(
              data['requested_at']!, _requestedAtMeta));
    } else if (isInserting) {
      context.missing(_requestedAtMeta);
    }
    if (data.containsKey('cost')) {
      context.handle(
          _costMeta, cost.isAcceptableOrUnknown(data['cost']!, _costMeta));
    } else if (isInserting) {
      context.missing(_costMeta);
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('auto_approved')) {
      context.handle(
          _autoApprovedMeta,
          autoApproved.isAcceptableOrUnknown(
              data['auto_approved']!, _autoApprovedMeta));
    }
    if (data.containsKey('queue_position')) {
      context.handle(
          _queuePositionMeta,
          queuePosition.isAcceptableOrUnknown(
              data['queue_position']!, _queuePositionMeta));
    }
    if (data.containsKey('verified_at')) {
      context.handle(
          _verifiedAtMeta,
          verifiedAt.isAcceptableOrUnknown(
              data['verified_at']!, _verifiedAtMeta));
    }
    if (data.containsKey('parent_note')) {
      context.handle(
          _parentNoteMeta,
          parentNote.isAcceptableOrUnknown(
              data['parent_note']!, _parentNoteMeta));
    }
    if (data.containsKey('child_id')) {
      context.handle(_childIdMeta,
          childId.isAcceptableOrUnknown(data['child_id']!, _childIdMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RedemptionRequest map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RedemptionRequest(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      templateId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}template_id'])!,
      requestedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}requested_at'])!,
      cost: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}cost'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}status'])!,
      autoApproved: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}auto_approved'])!,
      queuePosition: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}queue_position']),
      verifiedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}verified_at']),
      parentNote: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}parent_note']),
      childId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}child_id'])!,
    );
  }

  @override
  $RedemptionRequestsTable createAlias(String alias) {
    return $RedemptionRequestsTable(attachedDatabase, alias);
  }
}

class RedemptionRequest extends DataClass
    implements Insertable<RedemptionRequest> {
  final String id;
  final String templateId;
  final DateTime requestedAt;
  final int cost;
  final int status;
  final bool autoApproved;
  final int? queuePosition;
  final DateTime? verifiedAt;
  final String? parentNote;
  final String childId;
  const RedemptionRequest(
      {required this.id,
      required this.templateId,
      required this.requestedAt,
      required this.cost,
      required this.status,
      required this.autoApproved,
      this.queuePosition,
      this.verifiedAt,
      this.parentNote,
      required this.childId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['template_id'] = Variable<String>(templateId);
    map['requested_at'] = Variable<DateTime>(requestedAt);
    map['cost'] = Variable<int>(cost);
    map['status'] = Variable<int>(status);
    map['auto_approved'] = Variable<bool>(autoApproved);
    if (!nullToAbsent || queuePosition != null) {
      map['queue_position'] = Variable<int>(queuePosition);
    }
    if (!nullToAbsent || verifiedAt != null) {
      map['verified_at'] = Variable<DateTime>(verifiedAt);
    }
    if (!nullToAbsent || parentNote != null) {
      map['parent_note'] = Variable<String>(parentNote);
    }
    map['child_id'] = Variable<String>(childId);
    return map;
  }

  RedemptionRequestsCompanion toCompanion(bool nullToAbsent) {
    return RedemptionRequestsCompanion(
      id: Value(id),
      templateId: Value(templateId),
      requestedAt: Value(requestedAt),
      cost: Value(cost),
      status: Value(status),
      autoApproved: Value(autoApproved),
      queuePosition: queuePosition == null && nullToAbsent
          ? const Value.absent()
          : Value(queuePosition),
      verifiedAt: verifiedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(verifiedAt),
      parentNote: parentNote == null && nullToAbsent
          ? const Value.absent()
          : Value(parentNote),
      childId: Value(childId),
    );
  }

  factory RedemptionRequest.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RedemptionRequest(
      id: serializer.fromJson<String>(json['id']),
      templateId: serializer.fromJson<String>(json['templateId']),
      requestedAt: serializer.fromJson<DateTime>(json['requestedAt']),
      cost: serializer.fromJson<int>(json['cost']),
      status: serializer.fromJson<int>(json['status']),
      autoApproved: serializer.fromJson<bool>(json['autoApproved']),
      queuePosition: serializer.fromJson<int?>(json['queuePosition']),
      verifiedAt: serializer.fromJson<DateTime?>(json['verifiedAt']),
      parentNote: serializer.fromJson<String?>(json['parentNote']),
      childId: serializer.fromJson<String>(json['childId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'templateId': serializer.toJson<String>(templateId),
      'requestedAt': serializer.toJson<DateTime>(requestedAt),
      'cost': serializer.toJson<int>(cost),
      'status': serializer.toJson<int>(status),
      'autoApproved': serializer.toJson<bool>(autoApproved),
      'queuePosition': serializer.toJson<int?>(queuePosition),
      'verifiedAt': serializer.toJson<DateTime?>(verifiedAt),
      'parentNote': serializer.toJson<String?>(parentNote),
      'childId': serializer.toJson<String>(childId),
    };
  }

  RedemptionRequest copyWith(
          {String? id,
          String? templateId,
          DateTime? requestedAt,
          int? cost,
          int? status,
          bool? autoApproved,
          Value<int?> queuePosition = const Value.absent(),
          Value<DateTime?> verifiedAt = const Value.absent(),
          Value<String?> parentNote = const Value.absent(),
          String? childId}) =>
      RedemptionRequest(
        id: id ?? this.id,
        templateId: templateId ?? this.templateId,
        requestedAt: requestedAt ?? this.requestedAt,
        cost: cost ?? this.cost,
        status: status ?? this.status,
        autoApproved: autoApproved ?? this.autoApproved,
        queuePosition:
            queuePosition.present ? queuePosition.value : this.queuePosition,
        verifiedAt: verifiedAt.present ? verifiedAt.value : this.verifiedAt,
        parentNote: parentNote.present ? parentNote.value : this.parentNote,
        childId: childId ?? this.childId,
      );
  RedemptionRequest copyWithCompanion(RedemptionRequestsCompanion data) {
    return RedemptionRequest(
      id: data.id.present ? data.id.value : this.id,
      templateId:
          data.templateId.present ? data.templateId.value : this.templateId,
      requestedAt:
          data.requestedAt.present ? data.requestedAt.value : this.requestedAt,
      cost: data.cost.present ? data.cost.value : this.cost,
      status: data.status.present ? data.status.value : this.status,
      autoApproved: data.autoApproved.present
          ? data.autoApproved.value
          : this.autoApproved,
      queuePosition: data.queuePosition.present
          ? data.queuePosition.value
          : this.queuePosition,
      verifiedAt:
          data.verifiedAt.present ? data.verifiedAt.value : this.verifiedAt,
      parentNote:
          data.parentNote.present ? data.parentNote.value : this.parentNote,
      childId: data.childId.present ? data.childId.value : this.childId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RedemptionRequest(')
          ..write('id: $id, ')
          ..write('templateId: $templateId, ')
          ..write('requestedAt: $requestedAt, ')
          ..write('cost: $cost, ')
          ..write('status: $status, ')
          ..write('autoApproved: $autoApproved, ')
          ..write('queuePosition: $queuePosition, ')
          ..write('verifiedAt: $verifiedAt, ')
          ..write('parentNote: $parentNote, ')
          ..write('childId: $childId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, templateId, requestedAt, cost, status,
      autoApproved, queuePosition, verifiedAt, parentNote, childId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RedemptionRequest &&
          other.id == this.id &&
          other.templateId == this.templateId &&
          other.requestedAt == this.requestedAt &&
          other.cost == this.cost &&
          other.status == this.status &&
          other.autoApproved == this.autoApproved &&
          other.queuePosition == this.queuePosition &&
          other.verifiedAt == this.verifiedAt &&
          other.parentNote == this.parentNote &&
          other.childId == this.childId);
}

class RedemptionRequestsCompanion extends UpdateCompanion<RedemptionRequest> {
  final Value<String> id;
  final Value<String> templateId;
  final Value<DateTime> requestedAt;
  final Value<int> cost;
  final Value<int> status;
  final Value<bool> autoApproved;
  final Value<int?> queuePosition;
  final Value<DateTime?> verifiedAt;
  final Value<String?> parentNote;
  final Value<String> childId;
  final Value<int> rowid;
  const RedemptionRequestsCompanion({
    this.id = const Value.absent(),
    this.templateId = const Value.absent(),
    this.requestedAt = const Value.absent(),
    this.cost = const Value.absent(),
    this.status = const Value.absent(),
    this.autoApproved = const Value.absent(),
    this.queuePosition = const Value.absent(),
    this.verifiedAt = const Value.absent(),
    this.parentNote = const Value.absent(),
    this.childId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RedemptionRequestsCompanion.insert({
    required String id,
    required String templateId,
    required DateTime requestedAt,
    required int cost,
    required int status,
    this.autoApproved = const Value.absent(),
    this.queuePosition = const Value.absent(),
    this.verifiedAt = const Value.absent(),
    this.parentNote = const Value.absent(),
    this.childId = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        templateId = Value(templateId),
        requestedAt = Value(requestedAt),
        cost = Value(cost),
        status = Value(status);
  static Insertable<RedemptionRequest> custom({
    Expression<String>? id,
    Expression<String>? templateId,
    Expression<DateTime>? requestedAt,
    Expression<int>? cost,
    Expression<int>? status,
    Expression<bool>? autoApproved,
    Expression<int>? queuePosition,
    Expression<DateTime>? verifiedAt,
    Expression<String>? parentNote,
    Expression<String>? childId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (templateId != null) 'template_id': templateId,
      if (requestedAt != null) 'requested_at': requestedAt,
      if (cost != null) 'cost': cost,
      if (status != null) 'status': status,
      if (autoApproved != null) 'auto_approved': autoApproved,
      if (queuePosition != null) 'queue_position': queuePosition,
      if (verifiedAt != null) 'verified_at': verifiedAt,
      if (parentNote != null) 'parent_note': parentNote,
      if (childId != null) 'child_id': childId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RedemptionRequestsCompanion copyWith(
      {Value<String>? id,
      Value<String>? templateId,
      Value<DateTime>? requestedAt,
      Value<int>? cost,
      Value<int>? status,
      Value<bool>? autoApproved,
      Value<int?>? queuePosition,
      Value<DateTime?>? verifiedAt,
      Value<String?>? parentNote,
      Value<String>? childId,
      Value<int>? rowid}) {
    return RedemptionRequestsCompanion(
      id: id ?? this.id,
      templateId: templateId ?? this.templateId,
      requestedAt: requestedAt ?? this.requestedAt,
      cost: cost ?? this.cost,
      status: status ?? this.status,
      autoApproved: autoApproved ?? this.autoApproved,
      queuePosition: queuePosition ?? this.queuePosition,
      verifiedAt: verifiedAt ?? this.verifiedAt,
      parentNote: parentNote ?? this.parentNote,
      childId: childId ?? this.childId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (templateId.present) {
      map['template_id'] = Variable<String>(templateId.value);
    }
    if (requestedAt.present) {
      map['requested_at'] = Variable<DateTime>(requestedAt.value);
    }
    if (cost.present) {
      map['cost'] = Variable<int>(cost.value);
    }
    if (status.present) {
      map['status'] = Variable<int>(status.value);
    }
    if (autoApproved.present) {
      map['auto_approved'] = Variable<bool>(autoApproved.value);
    }
    if (queuePosition.present) {
      map['queue_position'] = Variable<int>(queuePosition.value);
    }
    if (verifiedAt.present) {
      map['verified_at'] = Variable<DateTime>(verifiedAt.value);
    }
    if (parentNote.present) {
      map['parent_note'] = Variable<String>(parentNote.value);
    }
    if (childId.present) {
      map['child_id'] = Variable<String>(childId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RedemptionRequestsCompanion(')
          ..write('id: $id, ')
          ..write('templateId: $templateId, ')
          ..write('requestedAt: $requestedAt, ')
          ..write('cost: $cost, ')
          ..write('status: $status, ')
          ..write('autoApproved: $autoApproved, ')
          ..write('queuePosition: $queuePosition, ')
          ..write('verifiedAt: $verifiedAt, ')
          ..write('parentNote: $parentNote, ')
          ..write('childId: $childId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MonthlyPoolsTable extends MonthlyPools
    with TableInfo<$MonthlyPoolsTable, MonthlyPool> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MonthlyPoolsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _monthKeyMeta =
      const VerificationMeta('monthKey');
  @override
  late final GeneratedColumn<String> monthKey = GeneratedColumn<String>(
      'month_key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _budgetMeta = const VerificationMeta('budget');
  @override
  late final GeneratedColumn<int> budget = GeneratedColumn<int>(
      'budget', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _usedMeta = const VerificationMeta('used');
  @override
  late final GeneratedColumn<int> used = GeneratedColumn<int>(
      'used', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _autoReleasedMeta =
      const VerificationMeta('autoReleased');
  @override
  late final GeneratedColumn<int> autoReleased = GeneratedColumn<int>(
      'auto_released', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _resetAtMeta =
      const VerificationMeta('resetAt');
  @override
  late final GeneratedColumn<DateTime> resetAt = GeneratedColumn<DateTime>(
      'reset_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [monthKey, budget, used, autoReleased, resetAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'monthly_pools';
  @override
  VerificationContext validateIntegrity(Insertable<MonthlyPool> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('month_key')) {
      context.handle(_monthKeyMeta,
          monthKey.isAcceptableOrUnknown(data['month_key']!, _monthKeyMeta));
    } else if (isInserting) {
      context.missing(_monthKeyMeta);
    }
    if (data.containsKey('budget')) {
      context.handle(_budgetMeta,
          budget.isAcceptableOrUnknown(data['budget']!, _budgetMeta));
    } else if (isInserting) {
      context.missing(_budgetMeta);
    }
    if (data.containsKey('used')) {
      context.handle(
          _usedMeta, used.isAcceptableOrUnknown(data['used']!, _usedMeta));
    }
    if (data.containsKey('auto_released')) {
      context.handle(
          _autoReleasedMeta,
          autoReleased.isAcceptableOrUnknown(
              data['auto_released']!, _autoReleasedMeta));
    }
    if (data.containsKey('reset_at')) {
      context.handle(_resetAtMeta,
          resetAt.isAcceptableOrUnknown(data['reset_at']!, _resetAtMeta));
    } else if (isInserting) {
      context.missing(_resetAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {monthKey};
  @override
  MonthlyPool map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MonthlyPool(
      monthKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}month_key'])!,
      budget: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}budget'])!,
      used: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}used'])!,
      autoReleased: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}auto_released'])!,
      resetAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}reset_at'])!,
    );
  }

  @override
  $MonthlyPoolsTable createAlias(String alias) {
    return $MonthlyPoolsTable(attachedDatabase, alias);
  }
}

class MonthlyPool extends DataClass implements Insertable<MonthlyPool> {
  final String monthKey;
  final int budget;
  final int used;
  final int autoReleased;
  final DateTime resetAt;
  const MonthlyPool(
      {required this.monthKey,
      required this.budget,
      required this.used,
      required this.autoReleased,
      required this.resetAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['month_key'] = Variable<String>(monthKey);
    map['budget'] = Variable<int>(budget);
    map['used'] = Variable<int>(used);
    map['auto_released'] = Variable<int>(autoReleased);
    map['reset_at'] = Variable<DateTime>(resetAt);
    return map;
  }

  MonthlyPoolsCompanion toCompanion(bool nullToAbsent) {
    return MonthlyPoolsCompanion(
      monthKey: Value(monthKey),
      budget: Value(budget),
      used: Value(used),
      autoReleased: Value(autoReleased),
      resetAt: Value(resetAt),
    );
  }

  factory MonthlyPool.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MonthlyPool(
      monthKey: serializer.fromJson<String>(json['monthKey']),
      budget: serializer.fromJson<int>(json['budget']),
      used: serializer.fromJson<int>(json['used']),
      autoReleased: serializer.fromJson<int>(json['autoReleased']),
      resetAt: serializer.fromJson<DateTime>(json['resetAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'monthKey': serializer.toJson<String>(monthKey),
      'budget': serializer.toJson<int>(budget),
      'used': serializer.toJson<int>(used),
      'autoReleased': serializer.toJson<int>(autoReleased),
      'resetAt': serializer.toJson<DateTime>(resetAt),
    };
  }

  MonthlyPool copyWith(
          {String? monthKey,
          int? budget,
          int? used,
          int? autoReleased,
          DateTime? resetAt}) =>
      MonthlyPool(
        monthKey: monthKey ?? this.monthKey,
        budget: budget ?? this.budget,
        used: used ?? this.used,
        autoReleased: autoReleased ?? this.autoReleased,
        resetAt: resetAt ?? this.resetAt,
      );
  MonthlyPool copyWithCompanion(MonthlyPoolsCompanion data) {
    return MonthlyPool(
      monthKey: data.monthKey.present ? data.monthKey.value : this.monthKey,
      budget: data.budget.present ? data.budget.value : this.budget,
      used: data.used.present ? data.used.value : this.used,
      autoReleased: data.autoReleased.present
          ? data.autoReleased.value
          : this.autoReleased,
      resetAt: data.resetAt.present ? data.resetAt.value : this.resetAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MonthlyPool(')
          ..write('monthKey: $monthKey, ')
          ..write('budget: $budget, ')
          ..write('used: $used, ')
          ..write('autoReleased: $autoReleased, ')
          ..write('resetAt: $resetAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(monthKey, budget, used, autoReleased, resetAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MonthlyPool &&
          other.monthKey == this.monthKey &&
          other.budget == this.budget &&
          other.used == this.used &&
          other.autoReleased == this.autoReleased &&
          other.resetAt == this.resetAt);
}

class MonthlyPoolsCompanion extends UpdateCompanion<MonthlyPool> {
  final Value<String> monthKey;
  final Value<int> budget;
  final Value<int> used;
  final Value<int> autoReleased;
  final Value<DateTime> resetAt;
  final Value<int> rowid;
  const MonthlyPoolsCompanion({
    this.monthKey = const Value.absent(),
    this.budget = const Value.absent(),
    this.used = const Value.absent(),
    this.autoReleased = const Value.absent(),
    this.resetAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MonthlyPoolsCompanion.insert({
    required String monthKey,
    required int budget,
    this.used = const Value.absent(),
    this.autoReleased = const Value.absent(),
    required DateTime resetAt,
    this.rowid = const Value.absent(),
  })  : monthKey = Value(monthKey),
        budget = Value(budget),
        resetAt = Value(resetAt);
  static Insertable<MonthlyPool> custom({
    Expression<String>? monthKey,
    Expression<int>? budget,
    Expression<int>? used,
    Expression<int>? autoReleased,
    Expression<DateTime>? resetAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (monthKey != null) 'month_key': monthKey,
      if (budget != null) 'budget': budget,
      if (used != null) 'used': used,
      if (autoReleased != null) 'auto_released': autoReleased,
      if (resetAt != null) 'reset_at': resetAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MonthlyPoolsCompanion copyWith(
      {Value<String>? monthKey,
      Value<int>? budget,
      Value<int>? used,
      Value<int>? autoReleased,
      Value<DateTime>? resetAt,
      Value<int>? rowid}) {
    return MonthlyPoolsCompanion(
      monthKey: monthKey ?? this.monthKey,
      budget: budget ?? this.budget,
      used: used ?? this.used,
      autoReleased: autoReleased ?? this.autoReleased,
      resetAt: resetAt ?? this.resetAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (monthKey.present) {
      map['month_key'] = Variable<String>(monthKey.value);
    }
    if (budget.present) {
      map['budget'] = Variable<int>(budget.value);
    }
    if (used.present) {
      map['used'] = Variable<int>(used.value);
    }
    if (autoReleased.present) {
      map['auto_released'] = Variable<int>(autoReleased.value);
    }
    if (resetAt.present) {
      map['reset_at'] = Variable<DateTime>(resetAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MonthlyPoolsCompanion(')
          ..write('monthKey: $monthKey, ')
          ..write('budget: $budget, ')
          ..write('used: $used, ')
          ..write('autoReleased: $autoReleased, ')
          ..write('resetAt: $resetAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TasksTable extends Tasks with TableInfo<$TasksTable, Task> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TasksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _subjectMeta =
      const VerificationMeta('subject');
  @override
  late final GeneratedColumn<int> subject = GeneratedColumn<int>(
      'subject', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _customSubjectMeta =
      const VerificationMeta('customSubject');
  @override
  late final GeneratedColumn<String> customSubject = GeneratedColumn<String>(
      'custom_subject', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _requiresFocusMeta =
      const VerificationMeta('requiresFocus');
  @override
  late final GeneratedColumn<bool> requiresFocus = GeneratedColumn<bool>(
      'requires_focus', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("requires_focus" IN (0, 1))'));
  static const VerificationMeta _minFocusMinMeta =
      const VerificationMeta('minFocusMin');
  @override
  late final GeneratedColumn<int> minFocusMin = GeneratedColumn<int>(
      'min_focus_min', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(kValidFocusMinutes));
  static const VerificationMeta _sunlightRewardMeta =
      const VerificationMeta('sunlightReward');
  @override
  late final GeneratedColumn<int> sunlightReward = GeneratedColumn<int>(
      'sunlight_reward', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(12));
  static const VerificationMeta _repeatRuleMeta =
      const VerificationMeta('repeatRule');
  @override
  late final GeneratedColumn<String> repeatRule = GeneratedColumn<String>(
      'repeat_rule', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isCustomMeta =
      const VerificationMeta('isCustom');
  @override
  late final GeneratedColumn<bool> isCustom = GeneratedColumn<bool>(
      'is_custom', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_custom" IN (0, 1))'));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        name,
        subject,
        customSubject,
        requiresFocus,
        minFocusMin,
        sunlightReward,
        repeatRule,
        isCustom
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tasks';
  @override
  VerificationContext validateIntegrity(Insertable<Task> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('subject')) {
      context.handle(_subjectMeta,
          subject.isAcceptableOrUnknown(data['subject']!, _subjectMeta));
    } else if (isInserting) {
      context.missing(_subjectMeta);
    }
    if (data.containsKey('custom_subject')) {
      context.handle(
          _customSubjectMeta,
          customSubject.isAcceptableOrUnknown(
              data['custom_subject']!, _customSubjectMeta));
    }
    if (data.containsKey('requires_focus')) {
      context.handle(
          _requiresFocusMeta,
          requiresFocus.isAcceptableOrUnknown(
              data['requires_focus']!, _requiresFocusMeta));
    } else if (isInserting) {
      context.missing(_requiresFocusMeta);
    }
    if (data.containsKey('min_focus_min')) {
      context.handle(
          _minFocusMinMeta,
          minFocusMin.isAcceptableOrUnknown(
              data['min_focus_min']!, _minFocusMinMeta));
    }
    if (data.containsKey('sunlight_reward')) {
      context.handle(
          _sunlightRewardMeta,
          sunlightReward.isAcceptableOrUnknown(
              data['sunlight_reward']!, _sunlightRewardMeta));
    }
    if (data.containsKey('repeat_rule')) {
      context.handle(
          _repeatRuleMeta,
          repeatRule.isAcceptableOrUnknown(
              data['repeat_rule']!, _repeatRuleMeta));
    }
    if (data.containsKey('is_custom')) {
      context.handle(_isCustomMeta,
          isCustom.isAcceptableOrUnknown(data['is_custom']!, _isCustomMeta));
    } else if (isInserting) {
      context.missing(_isCustomMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Task map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Task(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      subject: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}subject'])!,
      customSubject: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}custom_subject']),
      requiresFocus: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}requires_focus'])!,
      minFocusMin: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}min_focus_min'])!,
      sunlightReward: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sunlight_reward'])!,
      repeatRule: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}repeat_rule']),
      isCustom: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_custom'])!,
    );
  }

  @override
  $TasksTable createAlias(String alias) {
    return $TasksTable(attachedDatabase, alias);
  }
}

class Task extends DataClass implements Insertable<Task> {
  final String id;
  final String name;
  final int subject;
  final String? customSubject;
  final bool requiresFocus;
  final int minFocusMin;
  final int sunlightReward;
  final String? repeatRule;
  final bool isCustom;
  const Task(
      {required this.id,
      required this.name,
      required this.subject,
      this.customSubject,
      required this.requiresFocus,
      required this.minFocusMin,
      required this.sunlightReward,
      this.repeatRule,
      required this.isCustom});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['subject'] = Variable<int>(subject);
    if (!nullToAbsent || customSubject != null) {
      map['custom_subject'] = Variable<String>(customSubject);
    }
    map['requires_focus'] = Variable<bool>(requiresFocus);
    map['min_focus_min'] = Variable<int>(minFocusMin);
    map['sunlight_reward'] = Variable<int>(sunlightReward);
    if (!nullToAbsent || repeatRule != null) {
      map['repeat_rule'] = Variable<String>(repeatRule);
    }
    map['is_custom'] = Variable<bool>(isCustom);
    return map;
  }

  TasksCompanion toCompanion(bool nullToAbsent) {
    return TasksCompanion(
      id: Value(id),
      name: Value(name),
      subject: Value(subject),
      customSubject: customSubject == null && nullToAbsent
          ? const Value.absent()
          : Value(customSubject),
      requiresFocus: Value(requiresFocus),
      minFocusMin: Value(minFocusMin),
      sunlightReward: Value(sunlightReward),
      repeatRule: repeatRule == null && nullToAbsent
          ? const Value.absent()
          : Value(repeatRule),
      isCustom: Value(isCustom),
    );
  }

  factory Task.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Task(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      subject: serializer.fromJson<int>(json['subject']),
      customSubject: serializer.fromJson<String?>(json['customSubject']),
      requiresFocus: serializer.fromJson<bool>(json['requiresFocus']),
      minFocusMin: serializer.fromJson<int>(json['minFocusMin']),
      sunlightReward: serializer.fromJson<int>(json['sunlightReward']),
      repeatRule: serializer.fromJson<String?>(json['repeatRule']),
      isCustom: serializer.fromJson<bool>(json['isCustom']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'subject': serializer.toJson<int>(subject),
      'customSubject': serializer.toJson<String?>(customSubject),
      'requiresFocus': serializer.toJson<bool>(requiresFocus),
      'minFocusMin': serializer.toJson<int>(minFocusMin),
      'sunlightReward': serializer.toJson<int>(sunlightReward),
      'repeatRule': serializer.toJson<String?>(repeatRule),
      'isCustom': serializer.toJson<bool>(isCustom),
    };
  }

  Task copyWith(
          {String? id,
          String? name,
          int? subject,
          Value<String?> customSubject = const Value.absent(),
          bool? requiresFocus,
          int? minFocusMin,
          int? sunlightReward,
          Value<String?> repeatRule = const Value.absent(),
          bool? isCustom}) =>
      Task(
        id: id ?? this.id,
        name: name ?? this.name,
        subject: subject ?? this.subject,
        customSubject:
            customSubject.present ? customSubject.value : this.customSubject,
        requiresFocus: requiresFocus ?? this.requiresFocus,
        minFocusMin: minFocusMin ?? this.minFocusMin,
        sunlightReward: sunlightReward ?? this.sunlightReward,
        repeatRule: repeatRule.present ? repeatRule.value : this.repeatRule,
        isCustom: isCustom ?? this.isCustom,
      );
  Task copyWithCompanion(TasksCompanion data) {
    return Task(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      subject: data.subject.present ? data.subject.value : this.subject,
      customSubject: data.customSubject.present
          ? data.customSubject.value
          : this.customSubject,
      requiresFocus: data.requiresFocus.present
          ? data.requiresFocus.value
          : this.requiresFocus,
      minFocusMin:
          data.minFocusMin.present ? data.minFocusMin.value : this.minFocusMin,
      sunlightReward: data.sunlightReward.present
          ? data.sunlightReward.value
          : this.sunlightReward,
      repeatRule:
          data.repeatRule.present ? data.repeatRule.value : this.repeatRule,
      isCustom: data.isCustom.present ? data.isCustom.value : this.isCustom,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Task(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('subject: $subject, ')
          ..write('customSubject: $customSubject, ')
          ..write('requiresFocus: $requiresFocus, ')
          ..write('minFocusMin: $minFocusMin, ')
          ..write('sunlightReward: $sunlightReward, ')
          ..write('repeatRule: $repeatRule, ')
          ..write('isCustom: $isCustom')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, subject, customSubject,
      requiresFocus, minFocusMin, sunlightReward, repeatRule, isCustom);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Task &&
          other.id == this.id &&
          other.name == this.name &&
          other.subject == this.subject &&
          other.customSubject == this.customSubject &&
          other.requiresFocus == this.requiresFocus &&
          other.minFocusMin == this.minFocusMin &&
          other.sunlightReward == this.sunlightReward &&
          other.repeatRule == this.repeatRule &&
          other.isCustom == this.isCustom);
}

class TasksCompanion extends UpdateCompanion<Task> {
  final Value<String> id;
  final Value<String> name;
  final Value<int> subject;
  final Value<String?> customSubject;
  final Value<bool> requiresFocus;
  final Value<int> minFocusMin;
  final Value<int> sunlightReward;
  final Value<String?> repeatRule;
  final Value<bool> isCustom;
  final Value<int> rowid;
  const TasksCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.subject = const Value.absent(),
    this.customSubject = const Value.absent(),
    this.requiresFocus = const Value.absent(),
    this.minFocusMin = const Value.absent(),
    this.sunlightReward = const Value.absent(),
    this.repeatRule = const Value.absent(),
    this.isCustom = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TasksCompanion.insert({
    required String id,
    required String name,
    required int subject,
    this.customSubject = const Value.absent(),
    required bool requiresFocus,
    this.minFocusMin = const Value.absent(),
    this.sunlightReward = const Value.absent(),
    this.repeatRule = const Value.absent(),
    required bool isCustom,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        subject = Value(subject),
        requiresFocus = Value(requiresFocus),
        isCustom = Value(isCustom);
  static Insertable<Task> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? subject,
    Expression<String>? customSubject,
    Expression<bool>? requiresFocus,
    Expression<int>? minFocusMin,
    Expression<int>? sunlightReward,
    Expression<String>? repeatRule,
    Expression<bool>? isCustom,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (subject != null) 'subject': subject,
      if (customSubject != null) 'custom_subject': customSubject,
      if (requiresFocus != null) 'requires_focus': requiresFocus,
      if (minFocusMin != null) 'min_focus_min': minFocusMin,
      if (sunlightReward != null) 'sunlight_reward': sunlightReward,
      if (repeatRule != null) 'repeat_rule': repeatRule,
      if (isCustom != null) 'is_custom': isCustom,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TasksCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<int>? subject,
      Value<String?>? customSubject,
      Value<bool>? requiresFocus,
      Value<int>? minFocusMin,
      Value<int>? sunlightReward,
      Value<String?>? repeatRule,
      Value<bool>? isCustom,
      Value<int>? rowid}) {
    return TasksCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      subject: subject ?? this.subject,
      customSubject: customSubject ?? this.customSubject,
      requiresFocus: requiresFocus ?? this.requiresFocus,
      minFocusMin: minFocusMin ?? this.minFocusMin,
      sunlightReward: sunlightReward ?? this.sunlightReward,
      repeatRule: repeatRule ?? this.repeatRule,
      isCustom: isCustom ?? this.isCustom,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (subject.present) {
      map['subject'] = Variable<int>(subject.value);
    }
    if (customSubject.present) {
      map['custom_subject'] = Variable<String>(customSubject.value);
    }
    if (requiresFocus.present) {
      map['requires_focus'] = Variable<bool>(requiresFocus.value);
    }
    if (minFocusMin.present) {
      map['min_focus_min'] = Variable<int>(minFocusMin.value);
    }
    if (sunlightReward.present) {
      map['sunlight_reward'] = Variable<int>(sunlightReward.value);
    }
    if (repeatRule.present) {
      map['repeat_rule'] = Variable<String>(repeatRule.value);
    }
    if (isCustom.present) {
      map['is_custom'] = Variable<bool>(isCustom.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TasksCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('subject: $subject, ')
          ..write('customSubject: $customSubject, ')
          ..write('requiresFocus: $requiresFocus, ')
          ..write('minFocusMin: $minFocusMin, ')
          ..write('sunlightReward: $sunlightReward, ')
          ..write('repeatRule: $repeatRule, ')
          ..write('isCustom: $isCustom, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CheckInsTable extends CheckIns with TableInfo<$CheckInsTable, CheckIn> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CheckInsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  @override
  late final GeneratedColumn<String> taskId = GeneratedColumn<String>(
      'task_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<DateTime> date = GeneratedColumn<DateTime>(
      'date', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _completedAtMeta =
      const VerificationMeta('completedAt');
  @override
  late final GeneratedColumn<DateTime> completedAt = GeneratedColumn<DateTime>(
      'completed_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _sessionIdMeta =
      const VerificationMeta('sessionId');
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
      'session_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isPerfectDayMeta =
      const VerificationMeta('isPerfectDay');
  @override
  late final GeneratedColumn<bool> isPerfectDay = GeneratedColumn<bool>(
      'is_perfect_day', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("is_perfect_day" IN (0, 1))'));
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<int> status = GeneratedColumn<int>(
      'status', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _sunlightGrossMeta =
      const VerificationMeta('sunlightGross');
  @override
  late final GeneratedColumn<double> sunlightGross = GeneratedColumn<double>(
      'sunlight_gross', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(0.0));
  static const VerificationMeta _sunlightGrantedMeta =
      const VerificationMeta('sunlightGranted');
  @override
  late final GeneratedColumn<double> sunlightGranted = GeneratedColumn<double>(
      'sunlight_granted', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(0.0));
  static const VerificationMeta _resolvedAtMeta =
      const VerificationMeta('resolvedAt');
  @override
  late final GeneratedColumn<DateTime> resolvedAt = GeneratedColumn<DateTime>(
      'resolved_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _parentNoteMeta =
      const VerificationMeta('parentNote');
  @override
  late final GeneratedColumn<String> parentNote = GeneratedColumn<String>(
      'parent_note', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        taskId,
        date,
        completedAt,
        sessionId,
        isPerfectDay,
        status,
        sunlightGross,
        sunlightGranted,
        resolvedAt,
        parentNote
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'check_ins';
  @override
  VerificationContext validateIntegrity(Insertable<CheckIn> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('task_id')) {
      context.handle(_taskIdMeta,
          taskId.isAcceptableOrUnknown(data['task_id']!, _taskIdMeta));
    } else if (isInserting) {
      context.missing(_taskIdMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
          _dateMeta, date.isAcceptableOrUnknown(data['date']!, _dateMeta));
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('completed_at')) {
      context.handle(
          _completedAtMeta,
          completedAt.isAcceptableOrUnknown(
              data['completed_at']!, _completedAtMeta));
    } else if (isInserting) {
      context.missing(_completedAtMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(_sessionIdMeta,
          sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta));
    }
    if (data.containsKey('is_perfect_day')) {
      context.handle(
          _isPerfectDayMeta,
          isPerfectDay.isAcceptableOrUnknown(
              data['is_perfect_day']!, _isPerfectDayMeta));
    } else if (isInserting) {
      context.missing(_isPerfectDayMeta);
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('sunlight_gross')) {
      context.handle(
          _sunlightGrossMeta,
          sunlightGross.isAcceptableOrUnknown(
              data['sunlight_gross']!, _sunlightGrossMeta));
    }
    if (data.containsKey('sunlight_granted')) {
      context.handle(
          _sunlightGrantedMeta,
          sunlightGranted.isAcceptableOrUnknown(
              data['sunlight_granted']!, _sunlightGrantedMeta));
    }
    if (data.containsKey('resolved_at')) {
      context.handle(
          _resolvedAtMeta,
          resolvedAt.isAcceptableOrUnknown(
              data['resolved_at']!, _resolvedAtMeta));
    }
    if (data.containsKey('parent_note')) {
      context.handle(
          _parentNoteMeta,
          parentNote.isAcceptableOrUnknown(
              data['parent_note']!, _parentNoteMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CheckIn map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CheckIn(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      taskId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}task_id'])!,
      date: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}date'])!,
      completedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}completed_at'])!,
      sessionId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}session_id']),
      isPerfectDay: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_perfect_day'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}status'])!,
      sunlightGross: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}sunlight_gross'])!,
      sunlightGranted: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}sunlight_granted'])!,
      resolvedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}resolved_at']),
      parentNote: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}parent_note']),
    );
  }

  @override
  $CheckInsTable createAlias(String alias) {
    return $CheckInsTable(attachedDatabase, alias);
  }
}

class CheckIn extends DataClass implements Insertable<CheckIn> {
  final String id;
  final String taskId;
  final DateTime date;
  final DateTime completedAt;
  final String? sessionId;
  final bool isPerfectDay;
  final int status;
  final double sunlightGross;
  final double sunlightGranted;
  final DateTime? resolvedAt;
  final String? parentNote;
  const CheckIn(
      {required this.id,
      required this.taskId,
      required this.date,
      required this.completedAt,
      this.sessionId,
      required this.isPerfectDay,
      required this.status,
      required this.sunlightGross,
      required this.sunlightGranted,
      this.resolvedAt,
      this.parentNote});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['task_id'] = Variable<String>(taskId);
    map['date'] = Variable<DateTime>(date);
    map['completed_at'] = Variable<DateTime>(completedAt);
    if (!nullToAbsent || sessionId != null) {
      map['session_id'] = Variable<String>(sessionId);
    }
    map['is_perfect_day'] = Variable<bool>(isPerfectDay);
    map['status'] = Variable<int>(status);
    map['sunlight_gross'] = Variable<double>(sunlightGross);
    map['sunlight_granted'] = Variable<double>(sunlightGranted);
    if (!nullToAbsent || resolvedAt != null) {
      map['resolved_at'] = Variable<DateTime>(resolvedAt);
    }
    if (!nullToAbsent || parentNote != null) {
      map['parent_note'] = Variable<String>(parentNote);
    }
    return map;
  }

  CheckInsCompanion toCompanion(bool nullToAbsent) {
    return CheckInsCompanion(
      id: Value(id),
      taskId: Value(taskId),
      date: Value(date),
      completedAt: Value(completedAt),
      sessionId: sessionId == null && nullToAbsent
          ? const Value.absent()
          : Value(sessionId),
      isPerfectDay: Value(isPerfectDay),
      status: Value(status),
      sunlightGross: Value(sunlightGross),
      sunlightGranted: Value(sunlightGranted),
      resolvedAt: resolvedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(resolvedAt),
      parentNote: parentNote == null && nullToAbsent
          ? const Value.absent()
          : Value(parentNote),
    );
  }

  factory CheckIn.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CheckIn(
      id: serializer.fromJson<String>(json['id']),
      taskId: serializer.fromJson<String>(json['taskId']),
      date: serializer.fromJson<DateTime>(json['date']),
      completedAt: serializer.fromJson<DateTime>(json['completedAt']),
      sessionId: serializer.fromJson<String?>(json['sessionId']),
      isPerfectDay: serializer.fromJson<bool>(json['isPerfectDay']),
      status: serializer.fromJson<int>(json['status']),
      sunlightGross: serializer.fromJson<double>(json['sunlightGross']),
      sunlightGranted: serializer.fromJson<double>(json['sunlightGranted']),
      resolvedAt: serializer.fromJson<DateTime?>(json['resolvedAt']),
      parentNote: serializer.fromJson<String?>(json['parentNote']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'taskId': serializer.toJson<String>(taskId),
      'date': serializer.toJson<DateTime>(date),
      'completedAt': serializer.toJson<DateTime>(completedAt),
      'sessionId': serializer.toJson<String?>(sessionId),
      'isPerfectDay': serializer.toJson<bool>(isPerfectDay),
      'status': serializer.toJson<int>(status),
      'sunlightGross': serializer.toJson<double>(sunlightGross),
      'sunlightGranted': serializer.toJson<double>(sunlightGranted),
      'resolvedAt': serializer.toJson<DateTime?>(resolvedAt),
      'parentNote': serializer.toJson<String?>(parentNote),
    };
  }

  CheckIn copyWith(
          {String? id,
          String? taskId,
          DateTime? date,
          DateTime? completedAt,
          Value<String?> sessionId = const Value.absent(),
          bool? isPerfectDay,
          int? status,
          double? sunlightGross,
          double? sunlightGranted,
          Value<DateTime?> resolvedAt = const Value.absent(),
          Value<String?> parentNote = const Value.absent()}) =>
      CheckIn(
        id: id ?? this.id,
        taskId: taskId ?? this.taskId,
        date: date ?? this.date,
        completedAt: completedAt ?? this.completedAt,
        sessionId: sessionId.present ? sessionId.value : this.sessionId,
        isPerfectDay: isPerfectDay ?? this.isPerfectDay,
        status: status ?? this.status,
        sunlightGross: sunlightGross ?? this.sunlightGross,
        sunlightGranted: sunlightGranted ?? this.sunlightGranted,
        resolvedAt: resolvedAt.present ? resolvedAt.value : this.resolvedAt,
        parentNote: parentNote.present ? parentNote.value : this.parentNote,
      );
  CheckIn copyWithCompanion(CheckInsCompanion data) {
    return CheckIn(
      id: data.id.present ? data.id.value : this.id,
      taskId: data.taskId.present ? data.taskId.value : this.taskId,
      date: data.date.present ? data.date.value : this.date,
      completedAt:
          data.completedAt.present ? data.completedAt.value : this.completedAt,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      isPerfectDay: data.isPerfectDay.present
          ? data.isPerfectDay.value
          : this.isPerfectDay,
      status: data.status.present ? data.status.value : this.status,
      sunlightGross: data.sunlightGross.present
          ? data.sunlightGross.value
          : this.sunlightGross,
      sunlightGranted: data.sunlightGranted.present
          ? data.sunlightGranted.value
          : this.sunlightGranted,
      resolvedAt:
          data.resolvedAt.present ? data.resolvedAt.value : this.resolvedAt,
      parentNote:
          data.parentNote.present ? data.parentNote.value : this.parentNote,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CheckIn(')
          ..write('id: $id, ')
          ..write('taskId: $taskId, ')
          ..write('date: $date, ')
          ..write('completedAt: $completedAt, ')
          ..write('sessionId: $sessionId, ')
          ..write('isPerfectDay: $isPerfectDay, ')
          ..write('status: $status, ')
          ..write('sunlightGross: $sunlightGross, ')
          ..write('sunlightGranted: $sunlightGranted, ')
          ..write('resolvedAt: $resolvedAt, ')
          ..write('parentNote: $parentNote')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      taskId,
      date,
      completedAt,
      sessionId,
      isPerfectDay,
      status,
      sunlightGross,
      sunlightGranted,
      resolvedAt,
      parentNote);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CheckIn &&
          other.id == this.id &&
          other.taskId == this.taskId &&
          other.date == this.date &&
          other.completedAt == this.completedAt &&
          other.sessionId == this.sessionId &&
          other.isPerfectDay == this.isPerfectDay &&
          other.status == this.status &&
          other.sunlightGross == this.sunlightGross &&
          other.sunlightGranted == this.sunlightGranted &&
          other.resolvedAt == this.resolvedAt &&
          other.parentNote == this.parentNote);
}

class CheckInsCompanion extends UpdateCompanion<CheckIn> {
  final Value<String> id;
  final Value<String> taskId;
  final Value<DateTime> date;
  final Value<DateTime> completedAt;
  final Value<String?> sessionId;
  final Value<bool> isPerfectDay;
  final Value<int> status;
  final Value<double> sunlightGross;
  final Value<double> sunlightGranted;
  final Value<DateTime?> resolvedAt;
  final Value<String?> parentNote;
  final Value<int> rowid;
  const CheckInsCompanion({
    this.id = const Value.absent(),
    this.taskId = const Value.absent(),
    this.date = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.isPerfectDay = const Value.absent(),
    this.status = const Value.absent(),
    this.sunlightGross = const Value.absent(),
    this.sunlightGranted = const Value.absent(),
    this.resolvedAt = const Value.absent(),
    this.parentNote = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CheckInsCompanion.insert({
    required String id,
    required String taskId,
    required DateTime date,
    required DateTime completedAt,
    this.sessionId = const Value.absent(),
    required bool isPerfectDay,
    this.status = const Value.absent(),
    this.sunlightGross = const Value.absent(),
    this.sunlightGranted = const Value.absent(),
    this.resolvedAt = const Value.absent(),
    this.parentNote = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        taskId = Value(taskId),
        date = Value(date),
        completedAt = Value(completedAt),
        isPerfectDay = Value(isPerfectDay);
  static Insertable<CheckIn> custom({
    Expression<String>? id,
    Expression<String>? taskId,
    Expression<DateTime>? date,
    Expression<DateTime>? completedAt,
    Expression<String>? sessionId,
    Expression<bool>? isPerfectDay,
    Expression<int>? status,
    Expression<double>? sunlightGross,
    Expression<double>? sunlightGranted,
    Expression<DateTime>? resolvedAt,
    Expression<String>? parentNote,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (taskId != null) 'task_id': taskId,
      if (date != null) 'date': date,
      if (completedAt != null) 'completed_at': completedAt,
      if (sessionId != null) 'session_id': sessionId,
      if (isPerfectDay != null) 'is_perfect_day': isPerfectDay,
      if (status != null) 'status': status,
      if (sunlightGross != null) 'sunlight_gross': sunlightGross,
      if (sunlightGranted != null) 'sunlight_granted': sunlightGranted,
      if (resolvedAt != null) 'resolved_at': resolvedAt,
      if (parentNote != null) 'parent_note': parentNote,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CheckInsCompanion copyWith(
      {Value<String>? id,
      Value<String>? taskId,
      Value<DateTime>? date,
      Value<DateTime>? completedAt,
      Value<String?>? sessionId,
      Value<bool>? isPerfectDay,
      Value<int>? status,
      Value<double>? sunlightGross,
      Value<double>? sunlightGranted,
      Value<DateTime?>? resolvedAt,
      Value<String?>? parentNote,
      Value<int>? rowid}) {
    return CheckInsCompanion(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      date: date ?? this.date,
      completedAt: completedAt ?? this.completedAt,
      sessionId: sessionId ?? this.sessionId,
      isPerfectDay: isPerfectDay ?? this.isPerfectDay,
      status: status ?? this.status,
      sunlightGross: sunlightGross ?? this.sunlightGross,
      sunlightGranted: sunlightGranted ?? this.sunlightGranted,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      parentNote: parentNote ?? this.parentNote,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (taskId.present) {
      map['task_id'] = Variable<String>(taskId.value);
    }
    if (date.present) {
      map['date'] = Variable<DateTime>(date.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (isPerfectDay.present) {
      map['is_perfect_day'] = Variable<bool>(isPerfectDay.value);
    }
    if (status.present) {
      map['status'] = Variable<int>(status.value);
    }
    if (sunlightGross.present) {
      map['sunlight_gross'] = Variable<double>(sunlightGross.value);
    }
    if (sunlightGranted.present) {
      map['sunlight_granted'] = Variable<double>(sunlightGranted.value);
    }
    if (resolvedAt.present) {
      map['resolved_at'] = Variable<DateTime>(resolvedAt.value);
    }
    if (parentNote.present) {
      map['parent_note'] = Variable<String>(parentNote.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CheckInsCompanion(')
          ..write('id: $id, ')
          ..write('taskId: $taskId, ')
          ..write('date: $date, ')
          ..write('completedAt: $completedAt, ')
          ..write('sessionId: $sessionId, ')
          ..write('isPerfectDay: $isPerfectDay, ')
          ..write('status: $status, ')
          ..write('sunlightGross: $sunlightGross, ')
          ..write('sunlightGranted: $sunlightGranted, ')
          ..write('resolvedAt: $resolvedAt, ')
          ..write('parentNote: $parentNote, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CooldownCountersTable extends CooldownCounters
    with TableInfo<$CooldownCountersTable, CooldownCounter> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CooldownCountersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _templateIdMeta =
      const VerificationMeta('templateId');
  @override
  late final GeneratedColumn<String> templateId = GeneratedColumn<String>(
      'template_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _periodMeta = const VerificationMeta('period');
  @override
  late final GeneratedColumn<int> period = GeneratedColumn<int>(
      'period', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _usedCountMeta =
      const VerificationMeta('usedCount');
  @override
  late final GeneratedColumn<int> usedCount = GeneratedColumn<int>(
      'used_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  @override
  List<GeneratedColumn> get $columns => [templateId, period, usedCount];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cooldown_counters';
  @override
  VerificationContext validateIntegrity(Insertable<CooldownCounter> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('template_id')) {
      context.handle(
          _templateIdMeta,
          templateId.isAcceptableOrUnknown(
              data['template_id']!, _templateIdMeta));
    } else if (isInserting) {
      context.missing(_templateIdMeta);
    }
    if (data.containsKey('period')) {
      context.handle(_periodMeta,
          period.isAcceptableOrUnknown(data['period']!, _periodMeta));
    } else if (isInserting) {
      context.missing(_periodMeta);
    }
    if (data.containsKey('used_count')) {
      context.handle(_usedCountMeta,
          usedCount.isAcceptableOrUnknown(data['used_count']!, _usedCountMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {templateId, period};
  @override
  CooldownCounter map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CooldownCounter(
      templateId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}template_id'])!,
      period: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}period'])!,
      usedCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}used_count'])!,
    );
  }

  @override
  $CooldownCountersTable createAlias(String alias) {
    return $CooldownCountersTable(attachedDatabase, alias);
  }
}

class CooldownCounter extends DataClass implements Insertable<CooldownCounter> {
  final String templateId;
  final int period;
  final int usedCount;
  const CooldownCounter(
      {required this.templateId,
      required this.period,
      required this.usedCount});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['template_id'] = Variable<String>(templateId);
    map['period'] = Variable<int>(period);
    map['used_count'] = Variable<int>(usedCount);
    return map;
  }

  CooldownCountersCompanion toCompanion(bool nullToAbsent) {
    return CooldownCountersCompanion(
      templateId: Value(templateId),
      period: Value(period),
      usedCount: Value(usedCount),
    );
  }

  factory CooldownCounter.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CooldownCounter(
      templateId: serializer.fromJson<String>(json['templateId']),
      period: serializer.fromJson<int>(json['period']),
      usedCount: serializer.fromJson<int>(json['usedCount']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'templateId': serializer.toJson<String>(templateId),
      'period': serializer.toJson<int>(period),
      'usedCount': serializer.toJson<int>(usedCount),
    };
  }

  CooldownCounter copyWith({String? templateId, int? period, int? usedCount}) =>
      CooldownCounter(
        templateId: templateId ?? this.templateId,
        period: period ?? this.period,
        usedCount: usedCount ?? this.usedCount,
      );
  CooldownCounter copyWithCompanion(CooldownCountersCompanion data) {
    return CooldownCounter(
      templateId:
          data.templateId.present ? data.templateId.value : this.templateId,
      period: data.period.present ? data.period.value : this.period,
      usedCount: data.usedCount.present ? data.usedCount.value : this.usedCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CooldownCounter(')
          ..write('templateId: $templateId, ')
          ..write('period: $period, ')
          ..write('usedCount: $usedCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(templateId, period, usedCount);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CooldownCounter &&
          other.templateId == this.templateId &&
          other.period == this.period &&
          other.usedCount == this.usedCount);
}

class CooldownCountersCompanion extends UpdateCompanion<CooldownCounter> {
  final Value<String> templateId;
  final Value<int> period;
  final Value<int> usedCount;
  final Value<int> rowid;
  const CooldownCountersCompanion({
    this.templateId = const Value.absent(),
    this.period = const Value.absent(),
    this.usedCount = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CooldownCountersCompanion.insert({
    required String templateId,
    required int period,
    this.usedCount = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : templateId = Value(templateId),
        period = Value(period);
  static Insertable<CooldownCounter> custom({
    Expression<String>? templateId,
    Expression<int>? period,
    Expression<int>? usedCount,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (templateId != null) 'template_id': templateId,
      if (period != null) 'period': period,
      if (usedCount != null) 'used_count': usedCount,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CooldownCountersCompanion copyWith(
      {Value<String>? templateId,
      Value<int>? period,
      Value<int>? usedCount,
      Value<int>? rowid}) {
    return CooldownCountersCompanion(
      templateId: templateId ?? this.templateId,
      period: period ?? this.period,
      usedCount: usedCount ?? this.usedCount,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (templateId.present) {
      map['template_id'] = Variable<String>(templateId.value);
    }
    if (period.present) {
      map['period'] = Variable<int>(period.value);
    }
    if (usedCount.present) {
      map['used_count'] = Variable<int>(usedCount.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CooldownCountersCompanion(')
          ..write('templateId: $templateId, ')
          ..write('period: $period, ')
          ..write('usedCount: $usedCount, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TrackingEventsTable extends TrackingEvents
    with TableInfo<$TrackingEventsTable, TrackingEvent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TrackingEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<int> type = GeneratedColumn<int>(
      'type', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _tsMeta = const VerificationMeta('ts');
  @override
  late final GeneratedColumn<DateTime> ts = GeneratedColumn<DateTime>(
      'ts', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _payloadMeta =
      const VerificationMeta('payload');
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
      'payload', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [id, name, type, ts, payload];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tracking_events';
  @override
  VerificationContext validateIntegrity(Insertable<TrackingEvent> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('ts')) {
      context.handle(_tsMeta, ts.isAcceptableOrUnknown(data['ts']!, _tsMeta));
    } else if (isInserting) {
      context.missing(_tsMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(_payloadMeta,
          payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta));
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TrackingEvent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TrackingEvent(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}type'])!,
      ts: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}ts'])!,
      payload: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payload'])!,
    );
  }

  @override
  $TrackingEventsTable createAlias(String alias) {
    return $TrackingEventsTable(attachedDatabase, alias);
  }
}

class TrackingEvent extends DataClass implements Insertable<TrackingEvent> {
  final String id;
  final String name;
  final int type;
  final DateTime ts;
  final String payload;
  const TrackingEvent(
      {required this.id,
      required this.name,
      required this.type,
      required this.ts,
      required this.payload});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['type'] = Variable<int>(type);
    map['ts'] = Variable<DateTime>(ts);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  TrackingEventsCompanion toCompanion(bool nullToAbsent) {
    return TrackingEventsCompanion(
      id: Value(id),
      name: Value(name),
      type: Value(type),
      ts: Value(ts),
      payload: Value(payload),
    );
  }

  factory TrackingEvent.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TrackingEvent(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      type: serializer.fromJson<int>(json['type']),
      ts: serializer.fromJson<DateTime>(json['ts']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'type': serializer.toJson<int>(type),
      'ts': serializer.toJson<DateTime>(ts),
      'payload': serializer.toJson<String>(payload),
    };
  }

  TrackingEvent copyWith(
          {String? id,
          String? name,
          int? type,
          DateTime? ts,
          String? payload}) =>
      TrackingEvent(
        id: id ?? this.id,
        name: name ?? this.name,
        type: type ?? this.type,
        ts: ts ?? this.ts,
        payload: payload ?? this.payload,
      );
  TrackingEvent copyWithCompanion(TrackingEventsCompanion data) {
    return TrackingEvent(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      type: data.type.present ? data.type.value : this.type,
      ts: data.ts.present ? data.ts.value : this.ts,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TrackingEvent(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('ts: $ts, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, type, ts, payload);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TrackingEvent &&
          other.id == this.id &&
          other.name == this.name &&
          other.type == this.type &&
          other.ts == this.ts &&
          other.payload == this.payload);
}

class TrackingEventsCompanion extends UpdateCompanion<TrackingEvent> {
  final Value<String> id;
  final Value<String> name;
  final Value<int> type;
  final Value<DateTime> ts;
  final Value<String> payload;
  final Value<int> rowid;
  const TrackingEventsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.type = const Value.absent(),
    this.ts = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TrackingEventsCompanion.insert({
    required String id,
    this.name = const Value.absent(),
    required int type,
    required DateTime ts,
    required String payload,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        type = Value(type),
        ts = Value(ts),
        payload = Value(payload);
  static Insertable<TrackingEvent> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? type,
    Expression<DateTime>? ts,
    Expression<String>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (type != null) 'type': type,
      if (ts != null) 'ts': ts,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TrackingEventsCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<int>? type,
      Value<DateTime>? ts,
      Value<String>? payload,
      Value<int>? rowid}) {
    return TrackingEventsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      ts: ts ?? this.ts,
      payload: payload ?? this.payload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (type.present) {
      map['type'] = Variable<int>(type.value);
    }
    if (ts.present) {
      map['ts'] = Variable<DateTime>(ts.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TrackingEventsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('ts: $ts, ')
          ..write('payload: $payload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $SettingsTable settings = $SettingsTable(this);
  late final $PlantsTable plants = $PlantsTable(this);
  late final $FocusSessionsTable focusSessions = $FocusSessionsTable(this);
  late final $SunlightLedgersTable sunlightLedgers =
      $SunlightLedgersTable(this);
  late final $RewardTemplatesTable rewardTemplates =
      $RewardTemplatesTable(this);
  late final $RedemptionRequestsTable redemptionRequests =
      $RedemptionRequestsTable(this);
  late final $MonthlyPoolsTable monthlyPools = $MonthlyPoolsTable(this);
  late final $TasksTable tasks = $TasksTable(this);
  late final $CheckInsTable checkIns = $CheckInsTable(this);
  late final $CooldownCountersTable cooldownCounters =
      $CooldownCountersTable(this);
  late final $TrackingEventsTable trackingEvents = $TrackingEventsTable(this);
  late final SettingsDao settingsDao = SettingsDao(this as AppDatabase);
  late final PlantDao plantDao = PlantDao(this as AppDatabase);
  late final TaskDao taskDao = TaskDao(this as AppDatabase);
  late final SunlightLedgerDao sunlightLedgerDao =
      SunlightLedgerDao(this as AppDatabase);
  late final RewardTemplateDao rewardTemplateDao =
      RewardTemplateDao(this as AppDatabase);
  late final RedemptionRequestDao redemptionRequestDao =
      RedemptionRequestDao(this as AppDatabase);
  late final MonthlyPoolDao monthlyPoolDao =
      MonthlyPoolDao(this as AppDatabase);
  late final CooldownCounterDao cooldownCounterDao =
      CooldownCounterDao(this as AppDatabase);
  late final TrackingEventDao trackingEventDao =
      TrackingEventDao(this as AppDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        settings,
        plants,
        focusSessions,
        sunlightLedgers,
        rewardTemplates,
        redemptionRequests,
        monthlyPools,
        tasks,
        checkIns,
        cooldownCounters,
        trackingEvents
      ];
}

typedef $$SettingsTableCreateCompanionBuilder = SettingsCompanion Function({
  Value<int> id,
  required int ageTier,
  Value<int> nightBoundaryHour,
  Value<int> nightBoundaryMinute,
  required int dailyFocusCap,
  required int dailyAppCapMinutes,
  required int restAfterSessions,
  required int restMinutes,
  required int taskSunlight,
  required int monthlyPoolBudget,
  Value<bool> quietMode,
  Value<bool> soundOn,
  Value<bool> bgmOn,
  Value<bool> detectionOn,
  Value<int> autoConfirmSingleHigh,
  Value<int> autoConfirmSingleLow,
  Value<double> autoConfirmMonthlyPct,
  Value<double> currencyRate,
  Value<bool> themeDark,
  Value<bool> autonomousMode,
  Value<int> gardenPotCapacity,
});
typedef $$SettingsTableUpdateCompanionBuilder = SettingsCompanion Function({
  Value<int> id,
  Value<int> ageTier,
  Value<int> nightBoundaryHour,
  Value<int> nightBoundaryMinute,
  Value<int> dailyFocusCap,
  Value<int> dailyAppCapMinutes,
  Value<int> restAfterSessions,
  Value<int> restMinutes,
  Value<int> taskSunlight,
  Value<int> monthlyPoolBudget,
  Value<bool> quietMode,
  Value<bool> soundOn,
  Value<bool> bgmOn,
  Value<bool> detectionOn,
  Value<int> autoConfirmSingleHigh,
  Value<int> autoConfirmSingleLow,
  Value<double> autoConfirmMonthlyPct,
  Value<double> currencyRate,
  Value<bool> themeDark,
  Value<bool> autonomousMode,
  Value<int> gardenPotCapacity,
});

class $$SettingsTableFilterComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get ageTier => $composableBuilder(
      column: $table.ageTier, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get nightBoundaryHour => $composableBuilder(
      column: $table.nightBoundaryHour,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get nightBoundaryMinute => $composableBuilder(
      column: $table.nightBoundaryMinute,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get dailyFocusCap => $composableBuilder(
      column: $table.dailyFocusCap, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get dailyAppCapMinutes => $composableBuilder(
      column: $table.dailyAppCapMinutes,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get restAfterSessions => $composableBuilder(
      column: $table.restAfterSessions,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get restMinutes => $composableBuilder(
      column: $table.restMinutes, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get taskSunlight => $composableBuilder(
      column: $table.taskSunlight, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get monthlyPoolBudget => $composableBuilder(
      column: $table.monthlyPoolBudget,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get quietMode => $composableBuilder(
      column: $table.quietMode, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get soundOn => $composableBuilder(
      column: $table.soundOn, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get bgmOn => $composableBuilder(
      column: $table.bgmOn, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get detectionOn => $composableBuilder(
      column: $table.detectionOn, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get autoConfirmSingleHigh => $composableBuilder(
      column: $table.autoConfirmSingleHigh,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get autoConfirmSingleLow => $composableBuilder(
      column: $table.autoConfirmSingleLow,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get autoConfirmMonthlyPct => $composableBuilder(
      column: $table.autoConfirmMonthlyPct,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get currencyRate => $composableBuilder(
      column: $table.currencyRate, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get themeDark => $composableBuilder(
      column: $table.themeDark, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get autonomousMode => $composableBuilder(
      column: $table.autonomousMode,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get gardenPotCapacity => $composableBuilder(
      column: $table.gardenPotCapacity,
      builder: (column) => ColumnFilters(column));
}

class $$SettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get ageTier => $composableBuilder(
      column: $table.ageTier, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get nightBoundaryHour => $composableBuilder(
      column: $table.nightBoundaryHour,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get nightBoundaryMinute => $composableBuilder(
      column: $table.nightBoundaryMinute,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get dailyFocusCap => $composableBuilder(
      column: $table.dailyFocusCap,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get dailyAppCapMinutes => $composableBuilder(
      column: $table.dailyAppCapMinutes,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get restAfterSessions => $composableBuilder(
      column: $table.restAfterSessions,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get restMinutes => $composableBuilder(
      column: $table.restMinutes, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get taskSunlight => $composableBuilder(
      column: $table.taskSunlight,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get monthlyPoolBudget => $composableBuilder(
      column: $table.monthlyPoolBudget,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get quietMode => $composableBuilder(
      column: $table.quietMode, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get soundOn => $composableBuilder(
      column: $table.soundOn, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get bgmOn => $composableBuilder(
      column: $table.bgmOn, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get detectionOn => $composableBuilder(
      column: $table.detectionOn, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get autoConfirmSingleHigh => $composableBuilder(
      column: $table.autoConfirmSingleHigh,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get autoConfirmSingleLow => $composableBuilder(
      column: $table.autoConfirmSingleLow,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get autoConfirmMonthlyPct => $composableBuilder(
      column: $table.autoConfirmMonthlyPct,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get currencyRate => $composableBuilder(
      column: $table.currencyRate,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get themeDark => $composableBuilder(
      column: $table.themeDark, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get autonomousMode => $composableBuilder(
      column: $table.autonomousMode,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get gardenPotCapacity => $composableBuilder(
      column: $table.gardenPotCapacity,
      builder: (column) => ColumnOrderings(column));
}

class $$SettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get ageTier =>
      $composableBuilder(column: $table.ageTier, builder: (column) => column);

  GeneratedColumn<int> get nightBoundaryHour => $composableBuilder(
      column: $table.nightBoundaryHour, builder: (column) => column);

  GeneratedColumn<int> get nightBoundaryMinute => $composableBuilder(
      column: $table.nightBoundaryMinute, builder: (column) => column);

  GeneratedColumn<int> get dailyFocusCap => $composableBuilder(
      column: $table.dailyFocusCap, builder: (column) => column);

  GeneratedColumn<int> get dailyAppCapMinutes => $composableBuilder(
      column: $table.dailyAppCapMinutes, builder: (column) => column);

  GeneratedColumn<int> get restAfterSessions => $composableBuilder(
      column: $table.restAfterSessions, builder: (column) => column);

  GeneratedColumn<int> get restMinutes => $composableBuilder(
      column: $table.restMinutes, builder: (column) => column);

  GeneratedColumn<int> get taskSunlight => $composableBuilder(
      column: $table.taskSunlight, builder: (column) => column);

  GeneratedColumn<int> get monthlyPoolBudget => $composableBuilder(
      column: $table.monthlyPoolBudget, builder: (column) => column);

  GeneratedColumn<bool> get quietMode =>
      $composableBuilder(column: $table.quietMode, builder: (column) => column);

  GeneratedColumn<bool> get soundOn =>
      $composableBuilder(column: $table.soundOn, builder: (column) => column);

  GeneratedColumn<bool> get bgmOn =>
      $composableBuilder(column: $table.bgmOn, builder: (column) => column);

  GeneratedColumn<bool> get detectionOn => $composableBuilder(
      column: $table.detectionOn, builder: (column) => column);

  GeneratedColumn<int> get autoConfirmSingleHigh => $composableBuilder(
      column: $table.autoConfirmSingleHigh, builder: (column) => column);

  GeneratedColumn<int> get autoConfirmSingleLow => $composableBuilder(
      column: $table.autoConfirmSingleLow, builder: (column) => column);

  GeneratedColumn<double> get autoConfirmMonthlyPct => $composableBuilder(
      column: $table.autoConfirmMonthlyPct, builder: (column) => column);

  GeneratedColumn<double> get currencyRate => $composableBuilder(
      column: $table.currencyRate, builder: (column) => column);

  GeneratedColumn<bool> get themeDark =>
      $composableBuilder(column: $table.themeDark, builder: (column) => column);

  GeneratedColumn<bool> get autonomousMode => $composableBuilder(
      column: $table.autonomousMode, builder: (column) => column);

  GeneratedColumn<int> get gardenPotCapacity => $composableBuilder(
      column: $table.gardenPotCapacity, builder: (column) => column);
}

class $$SettingsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SettingsTable,
    Setting,
    $$SettingsTableFilterComposer,
    $$SettingsTableOrderingComposer,
    $$SettingsTableAnnotationComposer,
    $$SettingsTableCreateCompanionBuilder,
    $$SettingsTableUpdateCompanionBuilder,
    (Setting, BaseReferences<_$AppDatabase, $SettingsTable, Setting>),
    Setting,
    PrefetchHooks Function()> {
  $$SettingsTableTableManager(_$AppDatabase db, $SettingsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> ageTier = const Value.absent(),
            Value<int> nightBoundaryHour = const Value.absent(),
            Value<int> nightBoundaryMinute = const Value.absent(),
            Value<int> dailyFocusCap = const Value.absent(),
            Value<int> dailyAppCapMinutes = const Value.absent(),
            Value<int> restAfterSessions = const Value.absent(),
            Value<int> restMinutes = const Value.absent(),
            Value<int> taskSunlight = const Value.absent(),
            Value<int> monthlyPoolBudget = const Value.absent(),
            Value<bool> quietMode = const Value.absent(),
            Value<bool> soundOn = const Value.absent(),
            Value<bool> bgmOn = const Value.absent(),
            Value<bool> detectionOn = const Value.absent(),
            Value<int> autoConfirmSingleHigh = const Value.absent(),
            Value<int> autoConfirmSingleLow = const Value.absent(),
            Value<double> autoConfirmMonthlyPct = const Value.absent(),
            Value<double> currencyRate = const Value.absent(),
            Value<bool> themeDark = const Value.absent(),
            Value<bool> autonomousMode = const Value.absent(),
            Value<int> gardenPotCapacity = const Value.absent(),
          }) =>
              SettingsCompanion(
            id: id,
            ageTier: ageTier,
            nightBoundaryHour: nightBoundaryHour,
            nightBoundaryMinute: nightBoundaryMinute,
            dailyFocusCap: dailyFocusCap,
            dailyAppCapMinutes: dailyAppCapMinutes,
            restAfterSessions: restAfterSessions,
            restMinutes: restMinutes,
            taskSunlight: taskSunlight,
            monthlyPoolBudget: monthlyPoolBudget,
            quietMode: quietMode,
            soundOn: soundOn,
            bgmOn: bgmOn,
            detectionOn: detectionOn,
            autoConfirmSingleHigh: autoConfirmSingleHigh,
            autoConfirmSingleLow: autoConfirmSingleLow,
            autoConfirmMonthlyPct: autoConfirmMonthlyPct,
            currencyRate: currencyRate,
            themeDark: themeDark,
            autonomousMode: autonomousMode,
            gardenPotCapacity: gardenPotCapacity,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int ageTier,
            Value<int> nightBoundaryHour = const Value.absent(),
            Value<int> nightBoundaryMinute = const Value.absent(),
            required int dailyFocusCap,
            required int dailyAppCapMinutes,
            required int restAfterSessions,
            required int restMinutes,
            required int taskSunlight,
            required int monthlyPoolBudget,
            Value<bool> quietMode = const Value.absent(),
            Value<bool> soundOn = const Value.absent(),
            Value<bool> bgmOn = const Value.absent(),
            Value<bool> detectionOn = const Value.absent(),
            Value<int> autoConfirmSingleHigh = const Value.absent(),
            Value<int> autoConfirmSingleLow = const Value.absent(),
            Value<double> autoConfirmMonthlyPct = const Value.absent(),
            Value<double> currencyRate = const Value.absent(),
            Value<bool> themeDark = const Value.absent(),
            Value<bool> autonomousMode = const Value.absent(),
            Value<int> gardenPotCapacity = const Value.absent(),
          }) =>
              SettingsCompanion.insert(
            id: id,
            ageTier: ageTier,
            nightBoundaryHour: nightBoundaryHour,
            nightBoundaryMinute: nightBoundaryMinute,
            dailyFocusCap: dailyFocusCap,
            dailyAppCapMinutes: dailyAppCapMinutes,
            restAfterSessions: restAfterSessions,
            restMinutes: restMinutes,
            taskSunlight: taskSunlight,
            monthlyPoolBudget: monthlyPoolBudget,
            quietMode: quietMode,
            soundOn: soundOn,
            bgmOn: bgmOn,
            detectionOn: detectionOn,
            autoConfirmSingleHigh: autoConfirmSingleHigh,
            autoConfirmSingleLow: autoConfirmSingleLow,
            autoConfirmMonthlyPct: autoConfirmMonthlyPct,
            currencyRate: currencyRate,
            themeDark: themeDark,
            autonomousMode: autonomousMode,
            gardenPotCapacity: gardenPotCapacity,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SettingsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SettingsTable,
    Setting,
    $$SettingsTableFilterComposer,
    $$SettingsTableOrderingComposer,
    $$SettingsTableAnnotationComposer,
    $$SettingsTableCreateCompanionBuilder,
    $$SettingsTableUpdateCompanionBuilder,
    (Setting, BaseReferences<_$AppDatabase, $SettingsTable, Setting>),
    Setting,
    PrefetchHooks Function()>;
typedef $$PlantsTableCreateCompanionBuilder = PlantsCompanion Function({
  required String id,
  required String speciesId,
  required int potIndex,
  required int stage,
  required DateTime stageStartedAt,
  Value<double> growthProgress,
  Value<double> growthFactor,
  Value<bool> waterUsed,
  Value<bool> fertilizerUsed,
  required int status,
  required DateTime plantedAt,
  Value<DateTime?> lastWaterAt,
  Value<DateTime?> wiltedAt,
  Value<DateTime?> deadAt,
  Value<DateTime?> bloomedAt,
  Value<int> mood,
  Value<int> rowid,
});
typedef $$PlantsTableUpdateCompanionBuilder = PlantsCompanion Function({
  Value<String> id,
  Value<String> speciesId,
  Value<int> potIndex,
  Value<int> stage,
  Value<DateTime> stageStartedAt,
  Value<double> growthProgress,
  Value<double> growthFactor,
  Value<bool> waterUsed,
  Value<bool> fertilizerUsed,
  Value<int> status,
  Value<DateTime> plantedAt,
  Value<DateTime?> lastWaterAt,
  Value<DateTime?> wiltedAt,
  Value<DateTime?> deadAt,
  Value<DateTime?> bloomedAt,
  Value<int> mood,
  Value<int> rowid,
});

class $$PlantsTableFilterComposer
    extends Composer<_$AppDatabase, $PlantsTable> {
  $$PlantsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get speciesId => $composableBuilder(
      column: $table.speciesId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get potIndex => $composableBuilder(
      column: $table.potIndex, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get stage => $composableBuilder(
      column: $table.stage, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get stageStartedAt => $composableBuilder(
      column: $table.stageStartedAt,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get growthProgress => $composableBuilder(
      column: $table.growthProgress,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get growthFactor => $composableBuilder(
      column: $table.growthFactor, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get waterUsed => $composableBuilder(
      column: $table.waterUsed, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get fertilizerUsed => $composableBuilder(
      column: $table.fertilizerUsed,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get plantedAt => $composableBuilder(
      column: $table.plantedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastWaterAt => $composableBuilder(
      column: $table.lastWaterAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get wiltedAt => $composableBuilder(
      column: $table.wiltedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get deadAt => $composableBuilder(
      column: $table.deadAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get bloomedAt => $composableBuilder(
      column: $table.bloomedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get mood => $composableBuilder(
      column: $table.mood, builder: (column) => ColumnFilters(column));
}

class $$PlantsTableOrderingComposer
    extends Composer<_$AppDatabase, $PlantsTable> {
  $$PlantsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get speciesId => $composableBuilder(
      column: $table.speciesId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get potIndex => $composableBuilder(
      column: $table.potIndex, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get stage => $composableBuilder(
      column: $table.stage, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get stageStartedAt => $composableBuilder(
      column: $table.stageStartedAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get growthProgress => $composableBuilder(
      column: $table.growthProgress,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get growthFactor => $composableBuilder(
      column: $table.growthFactor,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get waterUsed => $composableBuilder(
      column: $table.waterUsed, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get fertilizerUsed => $composableBuilder(
      column: $table.fertilizerUsed,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get plantedAt => $composableBuilder(
      column: $table.plantedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastWaterAt => $composableBuilder(
      column: $table.lastWaterAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get wiltedAt => $composableBuilder(
      column: $table.wiltedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get deadAt => $composableBuilder(
      column: $table.deadAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get bloomedAt => $composableBuilder(
      column: $table.bloomedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get mood => $composableBuilder(
      column: $table.mood, builder: (column) => ColumnOrderings(column));
}

class $$PlantsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlantsTable> {
  $$PlantsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get speciesId =>
      $composableBuilder(column: $table.speciesId, builder: (column) => column);

  GeneratedColumn<int> get potIndex =>
      $composableBuilder(column: $table.potIndex, builder: (column) => column);

  GeneratedColumn<int> get stage =>
      $composableBuilder(column: $table.stage, builder: (column) => column);

  GeneratedColumn<DateTime> get stageStartedAt => $composableBuilder(
      column: $table.stageStartedAt, builder: (column) => column);

  GeneratedColumn<double> get growthProgress => $composableBuilder(
      column: $table.growthProgress, builder: (column) => column);

  GeneratedColumn<double> get growthFactor => $composableBuilder(
      column: $table.growthFactor, builder: (column) => column);

  GeneratedColumn<bool> get waterUsed =>
      $composableBuilder(column: $table.waterUsed, builder: (column) => column);

  GeneratedColumn<bool> get fertilizerUsed => $composableBuilder(
      column: $table.fertilizerUsed, builder: (column) => column);

  GeneratedColumn<int> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get plantedAt =>
      $composableBuilder(column: $table.plantedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastWaterAt => $composableBuilder(
      column: $table.lastWaterAt, builder: (column) => column);

  GeneratedColumn<DateTime> get wiltedAt =>
      $composableBuilder(column: $table.wiltedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deadAt =>
      $composableBuilder(column: $table.deadAt, builder: (column) => column);

  GeneratedColumn<DateTime> get bloomedAt =>
      $composableBuilder(column: $table.bloomedAt, builder: (column) => column);

  GeneratedColumn<int> get mood =>
      $composableBuilder(column: $table.mood, builder: (column) => column);
}

class $$PlantsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PlantsTable,
    Plant,
    $$PlantsTableFilterComposer,
    $$PlantsTableOrderingComposer,
    $$PlantsTableAnnotationComposer,
    $$PlantsTableCreateCompanionBuilder,
    $$PlantsTableUpdateCompanionBuilder,
    (Plant, BaseReferences<_$AppDatabase, $PlantsTable, Plant>),
    Plant,
    PrefetchHooks Function()> {
  $$PlantsTableTableManager(_$AppDatabase db, $PlantsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlantsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlantsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlantsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> speciesId = const Value.absent(),
            Value<int> potIndex = const Value.absent(),
            Value<int> stage = const Value.absent(),
            Value<DateTime> stageStartedAt = const Value.absent(),
            Value<double> growthProgress = const Value.absent(),
            Value<double> growthFactor = const Value.absent(),
            Value<bool> waterUsed = const Value.absent(),
            Value<bool> fertilizerUsed = const Value.absent(),
            Value<int> status = const Value.absent(),
            Value<DateTime> plantedAt = const Value.absent(),
            Value<DateTime?> lastWaterAt = const Value.absent(),
            Value<DateTime?> wiltedAt = const Value.absent(),
            Value<DateTime?> deadAt = const Value.absent(),
            Value<DateTime?> bloomedAt = const Value.absent(),
            Value<int> mood = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PlantsCompanion(
            id: id,
            speciesId: speciesId,
            potIndex: potIndex,
            stage: stage,
            stageStartedAt: stageStartedAt,
            growthProgress: growthProgress,
            growthFactor: growthFactor,
            waterUsed: waterUsed,
            fertilizerUsed: fertilizerUsed,
            status: status,
            plantedAt: plantedAt,
            lastWaterAt: lastWaterAt,
            wiltedAt: wiltedAt,
            deadAt: deadAt,
            bloomedAt: bloomedAt,
            mood: mood,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String speciesId,
            required int potIndex,
            required int stage,
            required DateTime stageStartedAt,
            Value<double> growthProgress = const Value.absent(),
            Value<double> growthFactor = const Value.absent(),
            Value<bool> waterUsed = const Value.absent(),
            Value<bool> fertilizerUsed = const Value.absent(),
            required int status,
            required DateTime plantedAt,
            Value<DateTime?> lastWaterAt = const Value.absent(),
            Value<DateTime?> wiltedAt = const Value.absent(),
            Value<DateTime?> deadAt = const Value.absent(),
            Value<DateTime?> bloomedAt = const Value.absent(),
            Value<int> mood = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PlantsCompanion.insert(
            id: id,
            speciesId: speciesId,
            potIndex: potIndex,
            stage: stage,
            stageStartedAt: stageStartedAt,
            growthProgress: growthProgress,
            growthFactor: growthFactor,
            waterUsed: waterUsed,
            fertilizerUsed: fertilizerUsed,
            status: status,
            plantedAt: plantedAt,
            lastWaterAt: lastWaterAt,
            wiltedAt: wiltedAt,
            deadAt: deadAt,
            bloomedAt: bloomedAt,
            mood: mood,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$PlantsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $PlantsTable,
    Plant,
    $$PlantsTableFilterComposer,
    $$PlantsTableOrderingComposer,
    $$PlantsTableAnnotationComposer,
    $$PlantsTableCreateCompanionBuilder,
    $$PlantsTableUpdateCompanionBuilder,
    (Plant, BaseReferences<_$AppDatabase, $PlantsTable, Plant>),
    Plant,
    PrefetchHooks Function()>;
typedef $$FocusSessionsTableCreateCompanionBuilder = FocusSessionsCompanion
    Function({
  required String id,
  required DateTime start,
  Value<DateTime?> end,
  required int plannedMin,
  required double actualFocusMin,
  required int status,
  required double sunlightEarned,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$FocusSessionsTableUpdateCompanionBuilder = FocusSessionsCompanion
    Function({
  Value<String> id,
  Value<DateTime> start,
  Value<DateTime?> end,
  Value<int> plannedMin,
  Value<double> actualFocusMin,
  Value<int> status,
  Value<double> sunlightEarned,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$FocusSessionsTableFilterComposer
    extends Composer<_$AppDatabase, $FocusSessionsTable> {
  $$FocusSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get start => $composableBuilder(
      column: $table.start, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get end => $composableBuilder(
      column: $table.end, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get plannedMin => $composableBuilder(
      column: $table.plannedMin, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get actualFocusMin => $composableBuilder(
      column: $table.actualFocusMin,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get sunlightEarned => $composableBuilder(
      column: $table.sunlightEarned,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$FocusSessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $FocusSessionsTable> {
  $$FocusSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get start => $composableBuilder(
      column: $table.start, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get end => $composableBuilder(
      column: $table.end, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get plannedMin => $composableBuilder(
      column: $table.plannedMin, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get actualFocusMin => $composableBuilder(
      column: $table.actualFocusMin,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get sunlightEarned => $composableBuilder(
      column: $table.sunlightEarned,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$FocusSessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $FocusSessionsTable> {
  $$FocusSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get start =>
      $composableBuilder(column: $table.start, builder: (column) => column);

  GeneratedColumn<DateTime> get end =>
      $composableBuilder(column: $table.end, builder: (column) => column);

  GeneratedColumn<int> get plannedMin => $composableBuilder(
      column: $table.plannedMin, builder: (column) => column);

  GeneratedColumn<double> get actualFocusMin => $composableBuilder(
      column: $table.actualFocusMin, builder: (column) => column);

  GeneratedColumn<int> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<double> get sunlightEarned => $composableBuilder(
      column: $table.sunlightEarned, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$FocusSessionsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $FocusSessionsTable,
    FocusSession,
    $$FocusSessionsTableFilterComposer,
    $$FocusSessionsTableOrderingComposer,
    $$FocusSessionsTableAnnotationComposer,
    $$FocusSessionsTableCreateCompanionBuilder,
    $$FocusSessionsTableUpdateCompanionBuilder,
    (
      FocusSession,
      BaseReferences<_$AppDatabase, $FocusSessionsTable, FocusSession>
    ),
    FocusSession,
    PrefetchHooks Function()> {
  $$FocusSessionsTableTableManager(_$AppDatabase db, $FocusSessionsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FocusSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FocusSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FocusSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<DateTime> start = const Value.absent(),
            Value<DateTime?> end = const Value.absent(),
            Value<int> plannedMin = const Value.absent(),
            Value<double> actualFocusMin = const Value.absent(),
            Value<int> status = const Value.absent(),
            Value<double> sunlightEarned = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              FocusSessionsCompanion(
            id: id,
            start: start,
            end: end,
            plannedMin: plannedMin,
            actualFocusMin: actualFocusMin,
            status: status,
            sunlightEarned: sunlightEarned,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required DateTime start,
            Value<DateTime?> end = const Value.absent(),
            required int plannedMin,
            required double actualFocusMin,
            required int status,
            required double sunlightEarned,
            required DateTime createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              FocusSessionsCompanion.insert(
            id: id,
            start: start,
            end: end,
            plannedMin: plannedMin,
            actualFocusMin: actualFocusMin,
            status: status,
            sunlightEarned: sunlightEarned,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$FocusSessionsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $FocusSessionsTable,
    FocusSession,
    $$FocusSessionsTableFilterComposer,
    $$FocusSessionsTableOrderingComposer,
    $$FocusSessionsTableAnnotationComposer,
    $$FocusSessionsTableCreateCompanionBuilder,
    $$FocusSessionsTableUpdateCompanionBuilder,
    (
      FocusSession,
      BaseReferences<_$AppDatabase, $FocusSessionsTable, FocusSession>
    ),
    FocusSession,
    PrefetchHooks Function()>;
typedef $$SunlightLedgersTableCreateCompanionBuilder = SunlightLedgersCompanion
    Function({
  required String id,
  required DateTime ts,
  required int type,
  required double gross,
  required double net,
  required double balanceAfter,
  Value<String?> refType,
  Value<String?> refId,
  required String dayKey,
  Value<int> rowid,
});
typedef $$SunlightLedgersTableUpdateCompanionBuilder = SunlightLedgersCompanion
    Function({
  Value<String> id,
  Value<DateTime> ts,
  Value<int> type,
  Value<double> gross,
  Value<double> net,
  Value<double> balanceAfter,
  Value<String?> refType,
  Value<String?> refId,
  Value<String> dayKey,
  Value<int> rowid,
});

class $$SunlightLedgersTableFilterComposer
    extends Composer<_$AppDatabase, $SunlightLedgersTable> {
  $$SunlightLedgersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get ts => $composableBuilder(
      column: $table.ts, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get gross => $composableBuilder(
      column: $table.gross, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get net => $composableBuilder(
      column: $table.net, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get balanceAfter => $composableBuilder(
      column: $table.balanceAfter, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get refType => $composableBuilder(
      column: $table.refType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get refId => $composableBuilder(
      column: $table.refId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get dayKey => $composableBuilder(
      column: $table.dayKey, builder: (column) => ColumnFilters(column));
}

class $$SunlightLedgersTableOrderingComposer
    extends Composer<_$AppDatabase, $SunlightLedgersTable> {
  $$SunlightLedgersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get ts => $composableBuilder(
      column: $table.ts, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get gross => $composableBuilder(
      column: $table.gross, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get net => $composableBuilder(
      column: $table.net, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get balanceAfter => $composableBuilder(
      column: $table.balanceAfter,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get refType => $composableBuilder(
      column: $table.refType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get refId => $composableBuilder(
      column: $table.refId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get dayKey => $composableBuilder(
      column: $table.dayKey, builder: (column) => ColumnOrderings(column));
}

class $$SunlightLedgersTableAnnotationComposer
    extends Composer<_$AppDatabase, $SunlightLedgersTable> {
  $$SunlightLedgersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get ts =>
      $composableBuilder(column: $table.ts, builder: (column) => column);

  GeneratedColumn<int> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<double> get gross =>
      $composableBuilder(column: $table.gross, builder: (column) => column);

  GeneratedColumn<double> get net =>
      $composableBuilder(column: $table.net, builder: (column) => column);

  GeneratedColumn<double> get balanceAfter => $composableBuilder(
      column: $table.balanceAfter, builder: (column) => column);

  GeneratedColumn<String> get refType =>
      $composableBuilder(column: $table.refType, builder: (column) => column);

  GeneratedColumn<String> get refId =>
      $composableBuilder(column: $table.refId, builder: (column) => column);

  GeneratedColumn<String> get dayKey =>
      $composableBuilder(column: $table.dayKey, builder: (column) => column);
}

class $$SunlightLedgersTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SunlightLedgersTable,
    SunlightLedger,
    $$SunlightLedgersTableFilterComposer,
    $$SunlightLedgersTableOrderingComposer,
    $$SunlightLedgersTableAnnotationComposer,
    $$SunlightLedgersTableCreateCompanionBuilder,
    $$SunlightLedgersTableUpdateCompanionBuilder,
    (
      SunlightLedger,
      BaseReferences<_$AppDatabase, $SunlightLedgersTable, SunlightLedger>
    ),
    SunlightLedger,
    PrefetchHooks Function()> {
  $$SunlightLedgersTableTableManager(
      _$AppDatabase db, $SunlightLedgersTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SunlightLedgersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SunlightLedgersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SunlightLedgersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<DateTime> ts = const Value.absent(),
            Value<int> type = const Value.absent(),
            Value<double> gross = const Value.absent(),
            Value<double> net = const Value.absent(),
            Value<double> balanceAfter = const Value.absent(),
            Value<String?> refType = const Value.absent(),
            Value<String?> refId = const Value.absent(),
            Value<String> dayKey = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SunlightLedgersCompanion(
            id: id,
            ts: ts,
            type: type,
            gross: gross,
            net: net,
            balanceAfter: balanceAfter,
            refType: refType,
            refId: refId,
            dayKey: dayKey,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required DateTime ts,
            required int type,
            required double gross,
            required double net,
            required double balanceAfter,
            Value<String?> refType = const Value.absent(),
            Value<String?> refId = const Value.absent(),
            required String dayKey,
            Value<int> rowid = const Value.absent(),
          }) =>
              SunlightLedgersCompanion.insert(
            id: id,
            ts: ts,
            type: type,
            gross: gross,
            net: net,
            balanceAfter: balanceAfter,
            refType: refType,
            refId: refId,
            dayKey: dayKey,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SunlightLedgersTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SunlightLedgersTable,
    SunlightLedger,
    $$SunlightLedgersTableFilterComposer,
    $$SunlightLedgersTableOrderingComposer,
    $$SunlightLedgersTableAnnotationComposer,
    $$SunlightLedgersTableCreateCompanionBuilder,
    $$SunlightLedgersTableUpdateCompanionBuilder,
    (
      SunlightLedger,
      BaseReferences<_$AppDatabase, $SunlightLedgersTable, SunlightLedger>
    ),
    SunlightLedger,
    PrefetchHooks Function()>;
typedef $$RewardTemplatesTableCreateCompanionBuilder = RewardTemplatesCompanion
    Function({
  required String id,
  required String name,
  required int category,
  Value<int> baseCost,
  Value<int?> freqLimit,
  Value<int> cooldownRule,
  Value<bool> enabled,
  Value<int> rowid,
});
typedef $$RewardTemplatesTableUpdateCompanionBuilder = RewardTemplatesCompanion
    Function({
  Value<String> id,
  Value<String> name,
  Value<int> category,
  Value<int> baseCost,
  Value<int?> freqLimit,
  Value<int> cooldownRule,
  Value<bool> enabled,
  Value<int> rowid,
});

class $$RewardTemplatesTableFilterComposer
    extends Composer<_$AppDatabase, $RewardTemplatesTable> {
  $$RewardTemplatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get category => $composableBuilder(
      column: $table.category, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get baseCost => $composableBuilder(
      column: $table.baseCost, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get freqLimit => $composableBuilder(
      column: $table.freqLimit, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get cooldownRule => $composableBuilder(
      column: $table.cooldownRule, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get enabled => $composableBuilder(
      column: $table.enabled, builder: (column) => ColumnFilters(column));
}

class $$RewardTemplatesTableOrderingComposer
    extends Composer<_$AppDatabase, $RewardTemplatesTable> {
  $$RewardTemplatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get category => $composableBuilder(
      column: $table.category, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get baseCost => $composableBuilder(
      column: $table.baseCost, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get freqLimit => $composableBuilder(
      column: $table.freqLimit, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get cooldownRule => $composableBuilder(
      column: $table.cooldownRule,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get enabled => $composableBuilder(
      column: $table.enabled, builder: (column) => ColumnOrderings(column));
}

class $$RewardTemplatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $RewardTemplatesTable> {
  $$RewardTemplatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<int> get baseCost =>
      $composableBuilder(column: $table.baseCost, builder: (column) => column);

  GeneratedColumn<int> get freqLimit =>
      $composableBuilder(column: $table.freqLimit, builder: (column) => column);

  GeneratedColumn<int> get cooldownRule => $composableBuilder(
      column: $table.cooldownRule, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);
}

class $$RewardTemplatesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $RewardTemplatesTable,
    RewardTemplate,
    $$RewardTemplatesTableFilterComposer,
    $$RewardTemplatesTableOrderingComposer,
    $$RewardTemplatesTableAnnotationComposer,
    $$RewardTemplatesTableCreateCompanionBuilder,
    $$RewardTemplatesTableUpdateCompanionBuilder,
    (
      RewardTemplate,
      BaseReferences<_$AppDatabase, $RewardTemplatesTable, RewardTemplate>
    ),
    RewardTemplate,
    PrefetchHooks Function()> {
  $$RewardTemplatesTableTableManager(
      _$AppDatabase db, $RewardTemplatesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RewardTemplatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RewardTemplatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RewardTemplatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<int> category = const Value.absent(),
            Value<int> baseCost = const Value.absent(),
            Value<int?> freqLimit = const Value.absent(),
            Value<int> cooldownRule = const Value.absent(),
            Value<bool> enabled = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              RewardTemplatesCompanion(
            id: id,
            name: name,
            category: category,
            baseCost: baseCost,
            freqLimit: freqLimit,
            cooldownRule: cooldownRule,
            enabled: enabled,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            required int category,
            Value<int> baseCost = const Value.absent(),
            Value<int?> freqLimit = const Value.absent(),
            Value<int> cooldownRule = const Value.absent(),
            Value<bool> enabled = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              RewardTemplatesCompanion.insert(
            id: id,
            name: name,
            category: category,
            baseCost: baseCost,
            freqLimit: freqLimit,
            cooldownRule: cooldownRule,
            enabled: enabled,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$RewardTemplatesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $RewardTemplatesTable,
    RewardTemplate,
    $$RewardTemplatesTableFilterComposer,
    $$RewardTemplatesTableOrderingComposer,
    $$RewardTemplatesTableAnnotationComposer,
    $$RewardTemplatesTableCreateCompanionBuilder,
    $$RewardTemplatesTableUpdateCompanionBuilder,
    (
      RewardTemplate,
      BaseReferences<_$AppDatabase, $RewardTemplatesTable, RewardTemplate>
    ),
    RewardTemplate,
    PrefetchHooks Function()>;
typedef $$RedemptionRequestsTableCreateCompanionBuilder
    = RedemptionRequestsCompanion Function({
  required String id,
  required String templateId,
  required DateTime requestedAt,
  required int cost,
  required int status,
  Value<bool> autoApproved,
  Value<int?> queuePosition,
  Value<DateTime?> verifiedAt,
  Value<String?> parentNote,
  Value<String> childId,
  Value<int> rowid,
});
typedef $$RedemptionRequestsTableUpdateCompanionBuilder
    = RedemptionRequestsCompanion Function({
  Value<String> id,
  Value<String> templateId,
  Value<DateTime> requestedAt,
  Value<int> cost,
  Value<int> status,
  Value<bool> autoApproved,
  Value<int?> queuePosition,
  Value<DateTime?> verifiedAt,
  Value<String?> parentNote,
  Value<String> childId,
  Value<int> rowid,
});

class $$RedemptionRequestsTableFilterComposer
    extends Composer<_$AppDatabase, $RedemptionRequestsTable> {
  $$RedemptionRequestsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get templateId => $composableBuilder(
      column: $table.templateId, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get requestedAt => $composableBuilder(
      column: $table.requestedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get cost => $composableBuilder(
      column: $table.cost, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get autoApproved => $composableBuilder(
      column: $table.autoApproved, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get queuePosition => $composableBuilder(
      column: $table.queuePosition, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get verifiedAt => $composableBuilder(
      column: $table.verifiedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get parentNote => $composableBuilder(
      column: $table.parentNote, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get childId => $composableBuilder(
      column: $table.childId, builder: (column) => ColumnFilters(column));
}

class $$RedemptionRequestsTableOrderingComposer
    extends Composer<_$AppDatabase, $RedemptionRequestsTable> {
  $$RedemptionRequestsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get templateId => $composableBuilder(
      column: $table.templateId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get requestedAt => $composableBuilder(
      column: $table.requestedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get cost => $composableBuilder(
      column: $table.cost, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get autoApproved => $composableBuilder(
      column: $table.autoApproved,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get queuePosition => $composableBuilder(
      column: $table.queuePosition,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get verifiedAt => $composableBuilder(
      column: $table.verifiedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get parentNote => $composableBuilder(
      column: $table.parentNote, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get childId => $composableBuilder(
      column: $table.childId, builder: (column) => ColumnOrderings(column));
}

class $$RedemptionRequestsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RedemptionRequestsTable> {
  $$RedemptionRequestsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get templateId => $composableBuilder(
      column: $table.templateId, builder: (column) => column);

  GeneratedColumn<DateTime> get requestedAt => $composableBuilder(
      column: $table.requestedAt, builder: (column) => column);

  GeneratedColumn<int> get cost =>
      $composableBuilder(column: $table.cost, builder: (column) => column);

  GeneratedColumn<int> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<bool> get autoApproved => $composableBuilder(
      column: $table.autoApproved, builder: (column) => column);

  GeneratedColumn<int> get queuePosition => $composableBuilder(
      column: $table.queuePosition, builder: (column) => column);

  GeneratedColumn<DateTime> get verifiedAt => $composableBuilder(
      column: $table.verifiedAt, builder: (column) => column);

  GeneratedColumn<String> get parentNote => $composableBuilder(
      column: $table.parentNote, builder: (column) => column);

  GeneratedColumn<String> get childId =>
      $composableBuilder(column: $table.childId, builder: (column) => column);
}

class $$RedemptionRequestsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $RedemptionRequestsTable,
    RedemptionRequest,
    $$RedemptionRequestsTableFilterComposer,
    $$RedemptionRequestsTableOrderingComposer,
    $$RedemptionRequestsTableAnnotationComposer,
    $$RedemptionRequestsTableCreateCompanionBuilder,
    $$RedemptionRequestsTableUpdateCompanionBuilder,
    (
      RedemptionRequest,
      BaseReferences<_$AppDatabase, $RedemptionRequestsTable, RedemptionRequest>
    ),
    RedemptionRequest,
    PrefetchHooks Function()> {
  $$RedemptionRequestsTableTableManager(
      _$AppDatabase db, $RedemptionRequestsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RedemptionRequestsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RedemptionRequestsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RedemptionRequestsTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> templateId = const Value.absent(),
            Value<DateTime> requestedAt = const Value.absent(),
            Value<int> cost = const Value.absent(),
            Value<int> status = const Value.absent(),
            Value<bool> autoApproved = const Value.absent(),
            Value<int?> queuePosition = const Value.absent(),
            Value<DateTime?> verifiedAt = const Value.absent(),
            Value<String?> parentNote = const Value.absent(),
            Value<String> childId = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              RedemptionRequestsCompanion(
            id: id,
            templateId: templateId,
            requestedAt: requestedAt,
            cost: cost,
            status: status,
            autoApproved: autoApproved,
            queuePosition: queuePosition,
            verifiedAt: verifiedAt,
            parentNote: parentNote,
            childId: childId,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String templateId,
            required DateTime requestedAt,
            required int cost,
            required int status,
            Value<bool> autoApproved = const Value.absent(),
            Value<int?> queuePosition = const Value.absent(),
            Value<DateTime?> verifiedAt = const Value.absent(),
            Value<String?> parentNote = const Value.absent(),
            Value<String> childId = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              RedemptionRequestsCompanion.insert(
            id: id,
            templateId: templateId,
            requestedAt: requestedAt,
            cost: cost,
            status: status,
            autoApproved: autoApproved,
            queuePosition: queuePosition,
            verifiedAt: verifiedAt,
            parentNote: parentNote,
            childId: childId,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$RedemptionRequestsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $RedemptionRequestsTable,
    RedemptionRequest,
    $$RedemptionRequestsTableFilterComposer,
    $$RedemptionRequestsTableOrderingComposer,
    $$RedemptionRequestsTableAnnotationComposer,
    $$RedemptionRequestsTableCreateCompanionBuilder,
    $$RedemptionRequestsTableUpdateCompanionBuilder,
    (
      RedemptionRequest,
      BaseReferences<_$AppDatabase, $RedemptionRequestsTable, RedemptionRequest>
    ),
    RedemptionRequest,
    PrefetchHooks Function()>;
typedef $$MonthlyPoolsTableCreateCompanionBuilder = MonthlyPoolsCompanion
    Function({
  required String monthKey,
  required int budget,
  Value<int> used,
  Value<int> autoReleased,
  required DateTime resetAt,
  Value<int> rowid,
});
typedef $$MonthlyPoolsTableUpdateCompanionBuilder = MonthlyPoolsCompanion
    Function({
  Value<String> monthKey,
  Value<int> budget,
  Value<int> used,
  Value<int> autoReleased,
  Value<DateTime> resetAt,
  Value<int> rowid,
});

class $$MonthlyPoolsTableFilterComposer
    extends Composer<_$AppDatabase, $MonthlyPoolsTable> {
  $$MonthlyPoolsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get monthKey => $composableBuilder(
      column: $table.monthKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get budget => $composableBuilder(
      column: $table.budget, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get used => $composableBuilder(
      column: $table.used, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get autoReleased => $composableBuilder(
      column: $table.autoReleased, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get resetAt => $composableBuilder(
      column: $table.resetAt, builder: (column) => ColumnFilters(column));
}

class $$MonthlyPoolsTableOrderingComposer
    extends Composer<_$AppDatabase, $MonthlyPoolsTable> {
  $$MonthlyPoolsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get monthKey => $composableBuilder(
      column: $table.monthKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get budget => $composableBuilder(
      column: $table.budget, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get used => $composableBuilder(
      column: $table.used, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get autoReleased => $composableBuilder(
      column: $table.autoReleased,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get resetAt => $composableBuilder(
      column: $table.resetAt, builder: (column) => ColumnOrderings(column));
}

class $$MonthlyPoolsTableAnnotationComposer
    extends Composer<_$AppDatabase, $MonthlyPoolsTable> {
  $$MonthlyPoolsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get monthKey =>
      $composableBuilder(column: $table.monthKey, builder: (column) => column);

  GeneratedColumn<int> get budget =>
      $composableBuilder(column: $table.budget, builder: (column) => column);

  GeneratedColumn<int> get used =>
      $composableBuilder(column: $table.used, builder: (column) => column);

  GeneratedColumn<int> get autoReleased => $composableBuilder(
      column: $table.autoReleased, builder: (column) => column);

  GeneratedColumn<DateTime> get resetAt =>
      $composableBuilder(column: $table.resetAt, builder: (column) => column);
}

class $$MonthlyPoolsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $MonthlyPoolsTable,
    MonthlyPool,
    $$MonthlyPoolsTableFilterComposer,
    $$MonthlyPoolsTableOrderingComposer,
    $$MonthlyPoolsTableAnnotationComposer,
    $$MonthlyPoolsTableCreateCompanionBuilder,
    $$MonthlyPoolsTableUpdateCompanionBuilder,
    (
      MonthlyPool,
      BaseReferences<_$AppDatabase, $MonthlyPoolsTable, MonthlyPool>
    ),
    MonthlyPool,
    PrefetchHooks Function()> {
  $$MonthlyPoolsTableTableManager(_$AppDatabase db, $MonthlyPoolsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MonthlyPoolsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MonthlyPoolsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MonthlyPoolsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> monthKey = const Value.absent(),
            Value<int> budget = const Value.absent(),
            Value<int> used = const Value.absent(),
            Value<int> autoReleased = const Value.absent(),
            Value<DateTime> resetAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MonthlyPoolsCompanion(
            monthKey: monthKey,
            budget: budget,
            used: used,
            autoReleased: autoReleased,
            resetAt: resetAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String monthKey,
            required int budget,
            Value<int> used = const Value.absent(),
            Value<int> autoReleased = const Value.absent(),
            required DateTime resetAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              MonthlyPoolsCompanion.insert(
            monthKey: monthKey,
            budget: budget,
            used: used,
            autoReleased: autoReleased,
            resetAt: resetAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$MonthlyPoolsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $MonthlyPoolsTable,
    MonthlyPool,
    $$MonthlyPoolsTableFilterComposer,
    $$MonthlyPoolsTableOrderingComposer,
    $$MonthlyPoolsTableAnnotationComposer,
    $$MonthlyPoolsTableCreateCompanionBuilder,
    $$MonthlyPoolsTableUpdateCompanionBuilder,
    (
      MonthlyPool,
      BaseReferences<_$AppDatabase, $MonthlyPoolsTable, MonthlyPool>
    ),
    MonthlyPool,
    PrefetchHooks Function()>;
typedef $$TasksTableCreateCompanionBuilder = TasksCompanion Function({
  required String id,
  required String name,
  required int subject,
  Value<String?> customSubject,
  required bool requiresFocus,
  Value<int> minFocusMin,
  Value<int> sunlightReward,
  Value<String?> repeatRule,
  required bool isCustom,
  Value<int> rowid,
});
typedef $$TasksTableUpdateCompanionBuilder = TasksCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<int> subject,
  Value<String?> customSubject,
  Value<bool> requiresFocus,
  Value<int> minFocusMin,
  Value<int> sunlightReward,
  Value<String?> repeatRule,
  Value<bool> isCustom,
  Value<int> rowid,
});

class $$TasksTableFilterComposer extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get subject => $composableBuilder(
      column: $table.subject, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get customSubject => $composableBuilder(
      column: $table.customSubject, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get requiresFocus => $composableBuilder(
      column: $table.requiresFocus, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get minFocusMin => $composableBuilder(
      column: $table.minFocusMin, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sunlightReward => $composableBuilder(
      column: $table.sunlightReward,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get repeatRule => $composableBuilder(
      column: $table.repeatRule, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isCustom => $composableBuilder(
      column: $table.isCustom, builder: (column) => ColumnFilters(column));
}

class $$TasksTableOrderingComposer
    extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get subject => $composableBuilder(
      column: $table.subject, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get customSubject => $composableBuilder(
      column: $table.customSubject,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get requiresFocus => $composableBuilder(
      column: $table.requiresFocus,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get minFocusMin => $composableBuilder(
      column: $table.minFocusMin, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sunlightReward => $composableBuilder(
      column: $table.sunlightReward,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get repeatRule => $composableBuilder(
      column: $table.repeatRule, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isCustom => $composableBuilder(
      column: $table.isCustom, builder: (column) => ColumnOrderings(column));
}

class $$TasksTableAnnotationComposer
    extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get subject =>
      $composableBuilder(column: $table.subject, builder: (column) => column);

  GeneratedColumn<String> get customSubject => $composableBuilder(
      column: $table.customSubject, builder: (column) => column);

  GeneratedColumn<bool> get requiresFocus => $composableBuilder(
      column: $table.requiresFocus, builder: (column) => column);

  GeneratedColumn<int> get minFocusMin => $composableBuilder(
      column: $table.minFocusMin, builder: (column) => column);

  GeneratedColumn<int> get sunlightReward => $composableBuilder(
      column: $table.sunlightReward, builder: (column) => column);

  GeneratedColumn<String> get repeatRule => $composableBuilder(
      column: $table.repeatRule, builder: (column) => column);

  GeneratedColumn<bool> get isCustom =>
      $composableBuilder(column: $table.isCustom, builder: (column) => column);
}

class $$TasksTableTableManager extends RootTableManager<
    _$AppDatabase,
    $TasksTable,
    Task,
    $$TasksTableFilterComposer,
    $$TasksTableOrderingComposer,
    $$TasksTableAnnotationComposer,
    $$TasksTableCreateCompanionBuilder,
    $$TasksTableUpdateCompanionBuilder,
    (Task, BaseReferences<_$AppDatabase, $TasksTable, Task>),
    Task,
    PrefetchHooks Function()> {
  $$TasksTableTableManager(_$AppDatabase db, $TasksTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TasksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TasksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TasksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<int> subject = const Value.absent(),
            Value<String?> customSubject = const Value.absent(),
            Value<bool> requiresFocus = const Value.absent(),
            Value<int> minFocusMin = const Value.absent(),
            Value<int> sunlightReward = const Value.absent(),
            Value<String?> repeatRule = const Value.absent(),
            Value<bool> isCustom = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              TasksCompanion(
            id: id,
            name: name,
            subject: subject,
            customSubject: customSubject,
            requiresFocus: requiresFocus,
            minFocusMin: minFocusMin,
            sunlightReward: sunlightReward,
            repeatRule: repeatRule,
            isCustom: isCustom,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            required int subject,
            Value<String?> customSubject = const Value.absent(),
            required bool requiresFocus,
            Value<int> minFocusMin = const Value.absent(),
            Value<int> sunlightReward = const Value.absent(),
            Value<String?> repeatRule = const Value.absent(),
            required bool isCustom,
            Value<int> rowid = const Value.absent(),
          }) =>
              TasksCompanion.insert(
            id: id,
            name: name,
            subject: subject,
            customSubject: customSubject,
            requiresFocus: requiresFocus,
            minFocusMin: minFocusMin,
            sunlightReward: sunlightReward,
            repeatRule: repeatRule,
            isCustom: isCustom,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$TasksTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $TasksTable,
    Task,
    $$TasksTableFilterComposer,
    $$TasksTableOrderingComposer,
    $$TasksTableAnnotationComposer,
    $$TasksTableCreateCompanionBuilder,
    $$TasksTableUpdateCompanionBuilder,
    (Task, BaseReferences<_$AppDatabase, $TasksTable, Task>),
    Task,
    PrefetchHooks Function()>;
typedef $$CheckInsTableCreateCompanionBuilder = CheckInsCompanion Function({
  required String id,
  required String taskId,
  required DateTime date,
  required DateTime completedAt,
  Value<String?> sessionId,
  required bool isPerfectDay,
  Value<int> status,
  Value<double> sunlightGross,
  Value<double> sunlightGranted,
  Value<DateTime?> resolvedAt,
  Value<String?> parentNote,
  Value<int> rowid,
});
typedef $$CheckInsTableUpdateCompanionBuilder = CheckInsCompanion Function({
  Value<String> id,
  Value<String> taskId,
  Value<DateTime> date,
  Value<DateTime> completedAt,
  Value<String?> sessionId,
  Value<bool> isPerfectDay,
  Value<int> status,
  Value<double> sunlightGross,
  Value<double> sunlightGranted,
  Value<DateTime?> resolvedAt,
  Value<String?> parentNote,
  Value<int> rowid,
});

class $$CheckInsTableFilterComposer
    extends Composer<_$AppDatabase, $CheckInsTable> {
  $$CheckInsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get taskId => $composableBuilder(
      column: $table.taskId, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get date => $composableBuilder(
      column: $table.date, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get completedAt => $composableBuilder(
      column: $table.completedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sessionId => $composableBuilder(
      column: $table.sessionId, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isPerfectDay => $composableBuilder(
      column: $table.isPerfectDay, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get sunlightGross => $composableBuilder(
      column: $table.sunlightGross, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get sunlightGranted => $composableBuilder(
      column: $table.sunlightGranted,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get resolvedAt => $composableBuilder(
      column: $table.resolvedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get parentNote => $composableBuilder(
      column: $table.parentNote, builder: (column) => ColumnFilters(column));
}

class $$CheckInsTableOrderingComposer
    extends Composer<_$AppDatabase, $CheckInsTable> {
  $$CheckInsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get taskId => $composableBuilder(
      column: $table.taskId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get date => $composableBuilder(
      column: $table.date, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get completedAt => $composableBuilder(
      column: $table.completedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sessionId => $composableBuilder(
      column: $table.sessionId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isPerfectDay => $composableBuilder(
      column: $table.isPerfectDay,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get sunlightGross => $composableBuilder(
      column: $table.sunlightGross,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get sunlightGranted => $composableBuilder(
      column: $table.sunlightGranted,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get resolvedAt => $composableBuilder(
      column: $table.resolvedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get parentNote => $composableBuilder(
      column: $table.parentNote, builder: (column) => ColumnOrderings(column));
}

class $$CheckInsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CheckInsTable> {
  $$CheckInsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get taskId =>
      $composableBuilder(column: $table.taskId, builder: (column) => column);

  GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<DateTime> get completedAt => $composableBuilder(
      column: $table.completedAt, builder: (column) => column);

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<bool> get isPerfectDay => $composableBuilder(
      column: $table.isPerfectDay, builder: (column) => column);

  GeneratedColumn<int> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<double> get sunlightGross => $composableBuilder(
      column: $table.sunlightGross, builder: (column) => column);

  GeneratedColumn<double> get sunlightGranted => $composableBuilder(
      column: $table.sunlightGranted, builder: (column) => column);

  GeneratedColumn<DateTime> get resolvedAt => $composableBuilder(
      column: $table.resolvedAt, builder: (column) => column);

  GeneratedColumn<String> get parentNote => $composableBuilder(
      column: $table.parentNote, builder: (column) => column);
}

class $$CheckInsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CheckInsTable,
    CheckIn,
    $$CheckInsTableFilterComposer,
    $$CheckInsTableOrderingComposer,
    $$CheckInsTableAnnotationComposer,
    $$CheckInsTableCreateCompanionBuilder,
    $$CheckInsTableUpdateCompanionBuilder,
    (CheckIn, BaseReferences<_$AppDatabase, $CheckInsTable, CheckIn>),
    CheckIn,
    PrefetchHooks Function()> {
  $$CheckInsTableTableManager(_$AppDatabase db, $CheckInsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CheckInsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CheckInsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CheckInsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> taskId = const Value.absent(),
            Value<DateTime> date = const Value.absent(),
            Value<DateTime> completedAt = const Value.absent(),
            Value<String?> sessionId = const Value.absent(),
            Value<bool> isPerfectDay = const Value.absent(),
            Value<int> status = const Value.absent(),
            Value<double> sunlightGross = const Value.absent(),
            Value<double> sunlightGranted = const Value.absent(),
            Value<DateTime?> resolvedAt = const Value.absent(),
            Value<String?> parentNote = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CheckInsCompanion(
            id: id,
            taskId: taskId,
            date: date,
            completedAt: completedAt,
            sessionId: sessionId,
            isPerfectDay: isPerfectDay,
            status: status,
            sunlightGross: sunlightGross,
            sunlightGranted: sunlightGranted,
            resolvedAt: resolvedAt,
            parentNote: parentNote,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String taskId,
            required DateTime date,
            required DateTime completedAt,
            Value<String?> sessionId = const Value.absent(),
            required bool isPerfectDay,
            Value<int> status = const Value.absent(),
            Value<double> sunlightGross = const Value.absent(),
            Value<double> sunlightGranted = const Value.absent(),
            Value<DateTime?> resolvedAt = const Value.absent(),
            Value<String?> parentNote = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CheckInsCompanion.insert(
            id: id,
            taskId: taskId,
            date: date,
            completedAt: completedAt,
            sessionId: sessionId,
            isPerfectDay: isPerfectDay,
            status: status,
            sunlightGross: sunlightGross,
            sunlightGranted: sunlightGranted,
            resolvedAt: resolvedAt,
            parentNote: parentNote,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CheckInsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CheckInsTable,
    CheckIn,
    $$CheckInsTableFilterComposer,
    $$CheckInsTableOrderingComposer,
    $$CheckInsTableAnnotationComposer,
    $$CheckInsTableCreateCompanionBuilder,
    $$CheckInsTableUpdateCompanionBuilder,
    (CheckIn, BaseReferences<_$AppDatabase, $CheckInsTable, CheckIn>),
    CheckIn,
    PrefetchHooks Function()>;
typedef $$CooldownCountersTableCreateCompanionBuilder
    = CooldownCountersCompanion Function({
  required String templateId,
  required int period,
  Value<int> usedCount,
  Value<int> rowid,
});
typedef $$CooldownCountersTableUpdateCompanionBuilder
    = CooldownCountersCompanion Function({
  Value<String> templateId,
  Value<int> period,
  Value<int> usedCount,
  Value<int> rowid,
});

class $$CooldownCountersTableFilterComposer
    extends Composer<_$AppDatabase, $CooldownCountersTable> {
  $$CooldownCountersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get templateId => $composableBuilder(
      column: $table.templateId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get period => $composableBuilder(
      column: $table.period, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get usedCount => $composableBuilder(
      column: $table.usedCount, builder: (column) => ColumnFilters(column));
}

class $$CooldownCountersTableOrderingComposer
    extends Composer<_$AppDatabase, $CooldownCountersTable> {
  $$CooldownCountersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get templateId => $composableBuilder(
      column: $table.templateId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get period => $composableBuilder(
      column: $table.period, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get usedCount => $composableBuilder(
      column: $table.usedCount, builder: (column) => ColumnOrderings(column));
}

class $$CooldownCountersTableAnnotationComposer
    extends Composer<_$AppDatabase, $CooldownCountersTable> {
  $$CooldownCountersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get templateId => $composableBuilder(
      column: $table.templateId, builder: (column) => column);

  GeneratedColumn<int> get period =>
      $composableBuilder(column: $table.period, builder: (column) => column);

  GeneratedColumn<int> get usedCount =>
      $composableBuilder(column: $table.usedCount, builder: (column) => column);
}

class $$CooldownCountersTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CooldownCountersTable,
    CooldownCounter,
    $$CooldownCountersTableFilterComposer,
    $$CooldownCountersTableOrderingComposer,
    $$CooldownCountersTableAnnotationComposer,
    $$CooldownCountersTableCreateCompanionBuilder,
    $$CooldownCountersTableUpdateCompanionBuilder,
    (
      CooldownCounter,
      BaseReferences<_$AppDatabase, $CooldownCountersTable, CooldownCounter>
    ),
    CooldownCounter,
    PrefetchHooks Function()> {
  $$CooldownCountersTableTableManager(
      _$AppDatabase db, $CooldownCountersTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CooldownCountersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CooldownCountersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CooldownCountersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> templateId = const Value.absent(),
            Value<int> period = const Value.absent(),
            Value<int> usedCount = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CooldownCountersCompanion(
            templateId: templateId,
            period: period,
            usedCount: usedCount,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String templateId,
            required int period,
            Value<int> usedCount = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CooldownCountersCompanion.insert(
            templateId: templateId,
            period: period,
            usedCount: usedCount,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CooldownCountersTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CooldownCountersTable,
    CooldownCounter,
    $$CooldownCountersTableFilterComposer,
    $$CooldownCountersTableOrderingComposer,
    $$CooldownCountersTableAnnotationComposer,
    $$CooldownCountersTableCreateCompanionBuilder,
    $$CooldownCountersTableUpdateCompanionBuilder,
    (
      CooldownCounter,
      BaseReferences<_$AppDatabase, $CooldownCountersTable, CooldownCounter>
    ),
    CooldownCounter,
    PrefetchHooks Function()>;
typedef $$TrackingEventsTableCreateCompanionBuilder = TrackingEventsCompanion
    Function({
  required String id,
  Value<String> name,
  required int type,
  required DateTime ts,
  required String payload,
  Value<int> rowid,
});
typedef $$TrackingEventsTableUpdateCompanionBuilder = TrackingEventsCompanion
    Function({
  Value<String> id,
  Value<String> name,
  Value<int> type,
  Value<DateTime> ts,
  Value<String> payload,
  Value<int> rowid,
});

class $$TrackingEventsTableFilterComposer
    extends Composer<_$AppDatabase, $TrackingEventsTable> {
  $$TrackingEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get ts => $composableBuilder(
      column: $table.ts, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnFilters(column));
}

class $$TrackingEventsTableOrderingComposer
    extends Composer<_$AppDatabase, $TrackingEventsTable> {
  $$TrackingEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get ts => $composableBuilder(
      column: $table.ts, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnOrderings(column));
}

class $$TrackingEventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TrackingEventsTable> {
  $$TrackingEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<DateTime> get ts =>
      $composableBuilder(column: $table.ts, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$TrackingEventsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $TrackingEventsTable,
    TrackingEvent,
    $$TrackingEventsTableFilterComposer,
    $$TrackingEventsTableOrderingComposer,
    $$TrackingEventsTableAnnotationComposer,
    $$TrackingEventsTableCreateCompanionBuilder,
    $$TrackingEventsTableUpdateCompanionBuilder,
    (
      TrackingEvent,
      BaseReferences<_$AppDatabase, $TrackingEventsTable, TrackingEvent>
    ),
    TrackingEvent,
    PrefetchHooks Function()> {
  $$TrackingEventsTableTableManager(
      _$AppDatabase db, $TrackingEventsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TrackingEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TrackingEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TrackingEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<int> type = const Value.absent(),
            Value<DateTime> ts = const Value.absent(),
            Value<String> payload = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              TrackingEventsCompanion(
            id: id,
            name: name,
            type: type,
            ts: ts,
            payload: payload,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            Value<String> name = const Value.absent(),
            required int type,
            required DateTime ts,
            required String payload,
            Value<int> rowid = const Value.absent(),
          }) =>
              TrackingEventsCompanion.insert(
            id: id,
            name: name,
            type: type,
            ts: ts,
            payload: payload,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$TrackingEventsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $TrackingEventsTable,
    TrackingEvent,
    $$TrackingEventsTableFilterComposer,
    $$TrackingEventsTableOrderingComposer,
    $$TrackingEventsTableAnnotationComposer,
    $$TrackingEventsTableCreateCompanionBuilder,
    $$TrackingEventsTableUpdateCompanionBuilder,
    (
      TrackingEvent,
      BaseReferences<_$AppDatabase, $TrackingEventsTable, TrackingEvent>
    ),
    TrackingEvent,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
  $$PlantsTableTableManager get plants =>
      $$PlantsTableTableManager(_db, _db.plants);
  $$FocusSessionsTableTableManager get focusSessions =>
      $$FocusSessionsTableTableManager(_db, _db.focusSessions);
  $$SunlightLedgersTableTableManager get sunlightLedgers =>
      $$SunlightLedgersTableTableManager(_db, _db.sunlightLedgers);
  $$RewardTemplatesTableTableManager get rewardTemplates =>
      $$RewardTemplatesTableTableManager(_db, _db.rewardTemplates);
  $$RedemptionRequestsTableTableManager get redemptionRequests =>
      $$RedemptionRequestsTableTableManager(_db, _db.redemptionRequests);
  $$MonthlyPoolsTableTableManager get monthlyPools =>
      $$MonthlyPoolsTableTableManager(_db, _db.monthlyPools);
  $$TasksTableTableManager get tasks =>
      $$TasksTableTableManager(_db, _db.tasks);
  $$CheckInsTableTableManager get checkIns =>
      $$CheckInsTableTableManager(_db, _db.checkIns);
  $$CooldownCountersTableTableManager get cooldownCounters =>
      $$CooldownCountersTableTableManager(_db, _db.cooldownCounters);
  $$TrackingEventsTableTableManager get trackingEvents =>
      $$TrackingEventsTableTableManager(_db, _db.trackingEvents);
}
