## Hive rules
-keep class com.hive_ce.** { *; }
-keepnames class * extends com.hive_ce.HiveObject
-keep class * extends com.hive_ce.TypeAdapter { *; }
-keep @com.hive_ce.HiveType class * { *; }
-keep @com.hive_ce.HiveField class * { *; }

## Keep generated adapters
-keep class **Adapter { *; }

## Odoo RPC rules (if needed)
-keep class odoo_rpc.** { *; }
