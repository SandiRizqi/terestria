package javax.lang.model;

/**
 * Android stub for javax.lang.model.SourceVersion.
 *
 * javax.lang.model is a Java SE annotation-processing API that does not exist
 * in the Android runtime.  GraphHopper (7.x+) calls SourceVersion.isIdentifier()
 * in IntEncodedValueImpl to validate encoded-value names such as "car" or "foot".
 *
 * This stub provides a minimal, correct implementation backed by
 * Character.isJavaIdentifierStart/Part which ARE present on all Android APIs.
 */
public enum SourceVersion {
    RELEASE_0, RELEASE_1, RELEASE_2, RELEASE_3, RELEASE_4, RELEASE_5,
    RELEASE_6, RELEASE_7, RELEASE_8, RELEASE_9, RELEASE_10,
    RELEASE_11, RELEASE_12, RELEASE_13, RELEASE_14, RELEASE_15,
    RELEASE_16, RELEASE_17;

    // ── static helpers used by GraphHopper ────────────────────────────────────

    /**
     * Returns true if {@code name} is a valid Java identifier
     * (e.g. "car", "foot", "myEncoder").
     */
    public static boolean isIdentifier(CharSequence name) {
        if (name == null) return false;
        int len = name.length();
        if (len == 0) return false;
        if (!Character.isJavaIdentifierStart(name.charAt(0))) return false;
        for (int i = 1; i < len; i++) {
            if (!Character.isJavaIdentifierPart(name.charAt(i))) return false;
        }
        return true;
    }

    /**
     * Returns true if {@code name} is a valid dot-separated Java name
     * (e.g. "com.example.Foo").
     */
    public static boolean isName(CharSequence name) {
        if (name == null || name.length() == 0) return false;
        for (String part : name.toString().split("\\.", -1)) {
            if (!isIdentifier(part)) return false;
        }
        return true;
    }

    /** Returns true if {@code s} is a Java keyword or reserved word. */
    public static boolean isKeyword(CharSequence s) {
        if (s == null) return false;
        switch (s.toString()) {
            case "abstract": case "assert":   case "boolean":   case "break":
            case "byte":     case "case":     case "catch":     case "char":
            case "class":    case "const":    case "continue":  case "default":
            case "do":       case "double":   case "else":      case "enum":
            case "extends":  case "final":    case "finally":   case "float":
            case "for":      case "if":       case "goto":      case "implements":
            case "import":   case "instanceof": case "int":     case "interface":
            case "long":     case "native":   case "new":       case "package":
            case "private":  case "protected": case "public":   case "return":
            case "short":    case "static":   case "strictfp":  case "super":
            case "switch":   case "synchronized": case "this":  case "throw":
            case "throws":   case "transient": case "try":      case "void":
            case "volatile": case "while":
                return true;
            default:
                return false;
        }
    }

    public static SourceVersion latestSupported() { return RELEASE_17; }
    public static SourceVersion latest()           { return RELEASE_17; }
}
