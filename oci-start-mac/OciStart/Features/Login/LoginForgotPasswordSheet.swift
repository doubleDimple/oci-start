import SwiftUI

/// Web-parity forgot-password modal (3 steps).
struct LoginForgotPasswordSheet: View {
    @ObservedObject var model: LoginFormModel
    var dark: Bool
    var onClose: () -> Void
    var onSendCode: () -> Void
    var onNext: () -> Void
    var onBack: () -> Void

    private var english: Bool { model.locale == .enUS }

    var body: some View {
        ZStack {
            Color.black.opacity(dark ? 0.65 : 0.45)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture { if !model.resetBusy { onClose() } }

            VStack(spacing: 0) {
                header
                stepIndicator
                    .padding(.horizontal, 28)
                    .padding(.top, 18)
                    .padding(.bottom, 8)
                content
                    .padding(.horizontal, 28)
                    .padding(.vertical, 16)
                if let msg = model.resetMessage {
                    Text(msg)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(model.resetMessageIsError
                                         ? Color(hex: "ef4444")
                                         : Color(hex: "22c55e"))
                        .padding(.horizontal, 28)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                actions
            }
            .frame(width: 460)
            .background(LoginPalette.card(dark))
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(LoginPalette.line(dark).opacity(0.8), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(dark ? 0.5 : 0.18), radius: 30, y: 12)
        }
        .onExitCommand { if !model.resetBusy { onClose() } }
    }

    private var header: some View {
        HStack {
            Text(english ? "Reset password" : "重置密码")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(LoginPalette.text(dark))
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(LoginPalette.muted(dark))
                    .frame(width: 32, height: 32)
                    .background(LoginPalette.oauthBg(dark).opacity(0.6))
                    .clipShape(Circle())
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(model.resetBusy)
            .accessibilityLabel(english ? "Close" : "关闭")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(LoginPalette.card(dark))
        .overlay(Rectangle().fill(LoginPalette.line(dark)).frame(height: 1), alignment: .bottom)
    }

    private var stepIndicator: some View {
        HStack(spacing: 0) {
            stepDot(1, english ? "Verify" : "验证身份")
            stepLine(active: model.resetStep >= 2)
            stepDot(2, english ? "Reset" : "重置密码")
            stepLine(active: model.resetStep >= 3)
            stepDot(3, english ? "Done" : "完成")
        }
    }

    private func stepDot(_ n: Int, _ title: String) -> some View {
        let active = model.resetStep == n
        let done = model.resetStep > n
        return VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(done || active ? LoginPalette.primary(dark) : LoginPalette.card(dark))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle().stroke(
                            done || active ? LoginPalette.primary(dark) : LoginPalette.line(dark),
                            lineWidth: 1.5
                        )
                    )
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Text("\(n)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(active ? .white : LoginPalette.muted(dark))
                }
            }
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(active || done ? LoginPalette.text(dark) : LoginPalette.muted(dark))
        }
        .frame(maxWidth: .infinity)
    }

    private func stepLine(active: Bool) -> some View {
        Rectangle()
            .fill(active ? LoginPalette.primary(dark) : LoginPalette.line(dark))
            .frame(height: 2)
            .frame(maxWidth: 48)
            .padding(.bottom, 18)
    }

    @ViewBuilder
    private var content: some View {
        switch model.resetStep {
        case 1:
            VStack(alignment: .leading, spacing: 14) {
                Text(english ? "Enter your username and request a verification code." : "输入用户名并获取验证码，完成身份验证。")
                    .font(.system(size: 13))
                    .foregroundColor(LoginPalette.muted(dark))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LoginPalette.panel(dark).opacity(0.6))
                    .cornerRadius(10)

                LoginField(
                    title: english ? "Username" : "用户名",
                    placeholder: english ? "Enter username" : "请输入用户名",
                    text: $model.resetUsername,
                    dark: dark,
                    enabled: !model.resetBusy
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text(english ? "Verification code" : "验证码")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(LoginPalette.text(dark))
                    HStack(alignment: .center, spacing: 12) {
                        LoginField(
                            title: "",
                            placeholder: english ? "Verification code" : "消息验证码",
                            text: $model.resetCode,
                            dark: dark,
                            enabled: !model.resetBusy
                        )
                        LoginFieldActionButton(
                            title: model.resetCodeCountdown > 0
                                ? "\(model.resetCodeCountdown)s"
                                : (model.resetSendingCode ? (english ? "Sending" : "发送中") : (english ? "Send code" : "发送验证码")),
                            loading: model.resetSendingCode,
                            enabled: !model.resetBusy
                                && model.resetCodeCountdown == 0
                                && !model.resetUsername.trimmingCharacters(in: .whitespaces).isEmpty,
                            dark: dark,
                            minWidth: 100,
                            action: onSendCode
                        )
                    }
                }
                .padding(.bottom, 6)
            }
        case 2:
            VStack(alignment: .leading, spacing: 14) {
                Text(english ? "Confirm to generate a new password for this account." : "确认后将为此账号生成新密码。")
                    .font(.system(size: 13))
                    .foregroundColor(LoginPalette.muted(dark))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LoginPalette.panel(dark).opacity(0.6))
                    .cornerRadius(10)
                VStack(alignment: .leading, spacing: 8) {
                    Text(english ? "Account" : "账号")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(LoginPalette.muted(dark))
                    Text(model.resetUsername)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(LoginPalette.text(dark))
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LoginPalette.oauthBg(dark))
                .cornerRadius(12)
            }
        default:
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 42))
                    .foregroundColor(Color(hex: "22c55e"))
                Text(english ? "Password reset" : "密码重置成功")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(LoginPalette.text(dark))
                Text(model.resetSuccessDetail.isEmpty
                     ? (english ? "Check your configured notification channel for the new password." : "请查看已配置的通知渠道，使用新密码登录。")
                     : model.resetSuccessDetail)
                    .font(.system(size: 13))
                    .foregroundColor(LoginPalette.muted(dark))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button(action: {
                if model.resetStep == 1 || model.resetStep == 3 {
                    onClose()
                } else {
                    onBack()
                }
            }) {
                Text(model.resetStep == 3 ? (english ? "Done" : "完成") : (model.resetStep == 1 ? (english ? "Cancel" : "取消") : (english ? "Back" : "上一步")))
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .foregroundColor(LoginPalette.text(dark))
                    .background(LoginPalette.oauthBg(dark))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(LoginPalette.oauthBorder(dark), lineWidth: 1)
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(model.resetBusy)

            if model.resetStep < 3 {
                Button(action: onNext) {
                    HStack(spacing: 8) {
                        if model.resetBusy {
                            ProgressView().scaleEffect(0.7)
                        }
                        Text(model.resetStep == 1 ? (english ? "Continue" : "下一步") : (english ? "Reset password" : "确认重置"))
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .foregroundColor(.white)
                    .background(LoginPalette.primary(dark))
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(model.resetBusy)
                .opacity(model.resetBusy ? 0.7 : 1)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(LoginPalette.card(dark))
        .overlay(Rectangle().fill(LoginPalette.line(dark)).frame(height: 1), alignment: .top)
    }
}
