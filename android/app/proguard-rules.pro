# WorkManager (NetWatch) creates its Room database by reflection on the
# generated *_Impl class. Without this rule R8 removes it and the app crashes
# at startup in androidx.startup.InitializationProvider.
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
