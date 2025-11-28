import 'package:flutter/material.dart';

class AppTheme {
  // Modern Green Color Palette
  static const Color primaryGreen = Color.fromARGB(255, 1, 130, 50); // Emerald Green
  static const Color lightGreen = Color.fromARGB(255, 89, 236, 131); // Light Green
  static const Color darkGreen = Color(0xFF047857); // Dark Green
  static const Color accentGreen = Color.fromARGB(255, 2, 158, 62); // Emerald Green
  
  static const Color primaryColor = primaryGreen;
  static const Color secondaryColor = lightGreen;
  static const Color errorColor = Color(0xFFEF4444);
  static const Color successColor = Color(0xFF10B981);
  static const Color warningColor = Color(0xFFF59E0B);
  
  // Text Colors
  static const Color textPrimary = Color(0xFF1F2937);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textLight = Colors.white;
  
  // Background Colors
  static const Color cardBackground = Colors.white;
  static const Color scaffoldBackground = Color(0xFFF9FAFB);
  static const Color inputBackground = Color(0xFFF3F4F6);
  
  // Map Colors
  static const Color pointColor = Color(0xFFEF4444); // Red
  static const Color lineColor = Color(0xFF3B82F6); // Blue
  static const Color polygonColor = primaryGreen;
  static const Color currentLocationColor = Color(0x4D10B981); // 30% opacity green
  
  // Border Radius
  static const double borderRadiusSmall = 8.0;
  static const double borderRadiusMedium = 12.0;
  static const double borderRadiusLarge = 20.0;
  static const double borderRadiusXLarge = 24.0;
  
  // Spacing
  static const double spacingXSmall = 4.0;
  static const double spacingSmall = 8.0;
  static const double spacingMedium = 16.0;
  static const double spacingLarge = 24.0;
  static const double spacingXLarge = 32.0;
  
  // Elevation
  static const double elevationLow = 0.0;
  static const double elevationMedium = 2.0;
  static const double elevationHigh = 8.0;

  static ThemeData lightTheme = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryGreen,
      primary: primaryGreen,
      secondary: lightGreen,
      surface: Colors.white,
      brightness: Brightness.light,
    ),
    useMaterial3: true,
    scaffoldBackgroundColor: scaffoldBackground,
    
    // AppBar Theme - Modern gradient style
    appBarTheme: const AppBarTheme(
      elevation: 0,
      centerTitle: false,
      backgroundColor: primaryGreen,
      foregroundColor: textLight,
      iconTheme: IconThemeData(color: textLight),
      titleTextStyle: TextStyle(
        color: textLight,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    ),
    
    // Card Theme - Elevated modern cards
    cardTheme: CardThemeData(
      elevation: elevationMedium,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadiusMedium),
      ),
      color: cardBackground,
      shadowColor: Colors.black.withOpacity(0.1),
    ),
    
    // Input Decoration Theme - Modern flat inputs
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadiusMedium),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadiusMedium),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadiusMedium),
        borderSide: const BorderSide(color: primaryGreen, width: 2),
      ),
      filled: true,
      fillColor: inputBackground,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: spacingMedium,
        vertical: spacingMedium,
      ),
    ),
    
    // Elevated Button Theme - Modern rounded buttons
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: elevationMedium,
        backgroundColor: primaryGreen,
        foregroundColor: textLight,
        padding: const EdgeInsets.symmetric(
          horizontal: spacingLarge,
          vertical: spacingMedium,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadiusMedium),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    
    // Outlined Button Theme
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primaryGreen,
        side: const BorderSide(color: primaryGreen, width: 2),
        padding: const EdgeInsets.symmetric(
          horizontal: spacingLarge,
          vertical: spacingMedium,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadiusMedium),
        ),
      ),
    ),
    
    // Text Button Theme
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primaryGreen,
        padding: const EdgeInsets.symmetric(
          horizontal: spacingMedium,
          vertical: spacingSmall,
        ),
      ),
    ),
    
    // Icon Button Theme
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: primaryGreen,
        padding: const EdgeInsets.all(spacingSmall),
      ),
    ),
    
    // FAB Theme - Circular modern FAB
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      elevation: elevationMedium,
      backgroundColor: primaryGreen,
      foregroundColor: textLight,
      shape: CircleBorder(),
    ),
    
    // Dialog Theme
    dialogTheme: DialogThemeData(
      elevation: elevationHigh,
      backgroundColor: cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadiusLarge),
      ),
    ),
    
    // Bottom Sheet Theme
    bottomSheetTheme: const BottomSheetThemeData(
      elevation: elevationHigh,
      backgroundColor: cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(borderRadiusLarge),
        ),
      ),
    ),
    
    // Chip Theme
    chipTheme: ChipThemeData(
      backgroundColor: lightGreen.withOpacity(0.2),
      labelStyle: const TextStyle(color: darkGreen),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadiusSmall),
      ),
    ),
    
    // Divider Theme
    dividerTheme: DividerThemeData(
      color: Colors.grey.shade200,
      thickness: 1,
      space: spacingMedium,
    ),
    
    // Progress Indicator Theme
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: primaryGreen,
    ),
    
    // Slider Theme
    sliderTheme: SliderThemeData(
      activeTrackColor: primaryGreen,
      inactiveTrackColor: Colors.grey.shade300,
      thumbColor: primaryGreen,
      overlayColor: primaryGreen.withOpacity(0.2),
    ),
    
    // Switch Theme
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return primaryGreen;
        }
        return Colors.grey;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return primaryGreen.withOpacity(0.5);
        }
        return Colors.grey.shade300;
      }),
    ),
  );

  static ThemeData darkTheme = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryGreen,
      primary: primaryGreen,
      secondary: lightGreen,
      brightness: Brightness.dark,
      surface: const Color(0xFF1F2937),
    ),
    useMaterial3: true,
    scaffoldBackgroundColor: const Color(0xFF111827),
    
    appBarTheme: const AppBarTheme(
      elevation: 0,
      centerTitle: false,
      backgroundColor: Color(0xFF1F2937),
      foregroundColor: textLight,
    ),
    
    cardTheme: CardThemeData(
      elevation: elevationMedium,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadiusMedium),
      ),
      color: const Color(0xFF1F2937),
    ),
    
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: primaryGreen,
      foregroundColor: textLight,
      shape: CircleBorder(),
    ),
  );
  
  // Helper method for gradient backgrounds
  static LinearGradient get primaryGradient => const LinearGradient(
    colors: [primaryGreen, accentGreen],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static LinearGradient get lightGradient => LinearGradient(
    colors: [lightGreen.withOpacity(0.1), primaryGreen.withOpacity(0.05)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
