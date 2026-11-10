// Hand-written: code that calls the vendor SDK lives in the generated
// package, guarded by the compilation condition husk_sdk defines.
#if HUSK_ACMEWIDGETSDK
import AcmeWidgetSDK
#endif

/// A greeting from AcmeWidgetSDK, or nil in a build without it.
public enum AcmeGreeter {
    public static func greeting(for name: String) -> String? {
        #if HUSK_ACMEWIDGETSDK
        return AcmeWidget.greeting(for: name)
        #else
        return nil
        #endif
    }
}
