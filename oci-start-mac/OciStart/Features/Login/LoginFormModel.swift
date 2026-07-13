import Foundation
import Combine

/// State for web-parity login form.
final class LoginFormModel: ObservableObject {
    enum Tab: String {
        case login
        case register
    }

    enum VerifyMethod {
        case message
        case mfa
    }

    @Published var tab: Tab = .login
    @Published var serverURL = "http://localhost:9856"
    @Published var username = ""
    @Published var password = ""
    @Published var confirmPassword = ""
    @Published var verificationCode = ""
    @Published var mfaCode = ""
    @Published var rememberMe = true
    @Published var showServer = false
    @Published var locale: AppLocale = .zhCN

    @Published var messageEnabled = false
    @Published var mfaEnabled = false
    @Published var allowRegister = false
    @Published var githubEnabled = false
    @Published var googleEnabled = false

    @Published var verifyMethod: VerifyMethod = .message
    @Published var errorText: String?
    @Published var infoText: String?
    @Published var isSubmitting = false
    @Published var isSendingCode = false
    @Published var codeCountdown = 0
    @Published var cryHero = false
    /// Password field focused → hero shy look-down (web).
    @Published var passwordFocused = false

    /// Login meta / factor APIs in flight for current serverURL.
    @Published var isLoadingMeta = false
    /// Last serverURL for which meta+factors finished successfully.
    @Published var metaLoadedURL: String?
    @Published var metaError: String?

    // Field shake tokens (web input-shake)
    @Published var shakeUsername = 0
    @Published var shakePassword = 0
    @Published var shakeConfirm = 0
    @Published var shakeVerify = 0
    @Published var shakeMfa = 0

    // Forgot password modal
    @Published var showForgotPassword = false
    @Published var resetStep = 1
    @Published var resetUsername = ""
    @Published var resetCode = ""
    @Published var resetToken: String?
    @Published var resetBusy = false
    @Published var resetSendingCode = false
    @Published var resetCodeCountdown = 0
    @Published var resetMessage: String?
    @Published var resetMessageIsError = false
    @Published var resetSuccessDetail = ""

    var showMessageCode: Bool {
        messageEnabled && (!mfaEnabled || verifyMethod == .message)
    }

    var showMfaCode: Bool {
        mfaEnabled && (!messageEnabled || verifyMethod == .mfa)
    }

    var showVerifyChoice: Bool {
        messageEnabled && mfaEnabled
    }

    var isRemoteServer: Bool {
        !AppSession.isLocalServerURL(serverURL)
    }

    /// Login button always pressable when form is ready — empty fields shake instead of hard-disable.
    func canAttemptLogin(backendReady: Bool) -> Bool {
        backendReady && !isSubmitting && !isLoadingMeta
    }

    func canAttemptRegister(backendReady: Bool) -> Bool {
        backendReady && !isSubmitting && !isLoadingMeta
    }

    /// Returns false if empty required fields (and bumps shake tokens).
    @discardableResult
    func validateLoginFields() -> Bool {
        var ok = true
        if username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            shakeUsername += 1
            ok = false
        }
        if password.isEmpty {
            shakePassword += 1
            ok = false
        }
        if showMessageCode && verificationCode.trimmingCharacters(in: .whitespaces).isEmpty {
            shakeVerify += 1
            ok = false
        }
        if showMfaCode && mfaCode.trimmingCharacters(in: .whitespaces).isEmpty {
            shakeMfa += 1
            ok = false
        }
        return ok
    }

    @discardableResult
    func validateRegisterFields() -> Bool {
        var ok = true
        if username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            shakeUsername += 1
            ok = false
        }
        if password.isEmpty {
            shakePassword += 1
            ok = false
        }
        if confirmPassword.isEmpty {
            shakeConfirm += 1
            ok = false
        }
        return ok
    }

    func openForgotPassword() {
        resetStep = 1
        resetUsername = username
        resetCode = ""
        resetToken = nil
        resetMessage = nil
        resetSuccessDetail = ""
        resetBusy = false
        showForgotPassword = true
    }

    func closeForgotPassword() {
        showForgotPassword = false
        resetBusy = false
        resetMessage = nil
    }
}
