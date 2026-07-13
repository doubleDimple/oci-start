import SwiftUI

/// Web-parity forgot-password modal (3 steps).
struct LoginForgotPasswordSheet: View {
    @ObservedObject var model: LoginFormModel
    var dark: Bool
    var onClose: () -> Void
    var onSendCode: () -> Void
    var onNext: () -> Void
    var onBack: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(dark ? 0.65 : 0.45)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture { onClose() }

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
            .frame(width: 560)
            .background(LoginPalette.card(dark))
            .cornerRadius(24)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(LoginPalette.line(dark).opacity(0.8), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(dark ? 0.5 : 0.18), radius: 30, y: 12)
        }
    }

    private var header: some View {
        HStack {
            Text("重置密码")
                .font(.system(size: 16, weight: .heavy))
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
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(LoginPalette.panel(dark).opacity(0.55))
        .overlay(Rectangle().fill(LoginPalette.line(dark)).frame(height: 1), alignment: .bottom)
    }

    private var stepIndicator: some View {
        HStack(spacing: 0) {
            stepDot(1, "验证身份")
            stepLine(active: model.resetStep >= 2)
            stepDot(2, "重置密码")
            stepLine(active: model.resetStep >= 3)
            stepDot(3, "完成")
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
                .font(.system(size: 11, weight: .semibold))
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
                Text("输入用户名并获取验证码，完成身份验证。")
                    .font(.system(size: 13))
                    .foregroundColor(LoginPalette.muted(dark))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LoginPalette.panel(dark).opacity(0.6))
                    .cornerRadius(10)

                LoginField(
                    title: "用户名",
                    placeholder: "请输入用户名",
                    text: $model.resetUsername,
                    dark: dark,
                    enabled: !model.resetBusy
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text("验证码")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundColor(LoginPalette.text(dark))
                    HStack(spacing: 12) {
                        LoginField(
                            title: "",
                            placeholder: "消息验证码",
                            text: $model.resetCode,
                            dark: dark,
                            enabled: !model.resetBusy
                        )
                        Button(action: onSendCode) {
                            Text(model.resetCodeCountdown > 0
                                 ? "\(model.resetCodeCountdown)s"
                                 : (model.resetSendingCode ? "发送中" : "发送验证码"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(LoginPalette.text(dark))
                                .padding(.horizontal, 14)
                                .frame(height: 44)
                                .background(LoginPalette.oauthBg(dark))
                                .cornerRadius(999)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 999)
                                        .stroke(LoginPalette.oauthBorder(dark), lineWidth: 1)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(model.resetBusy
                                  || model.resetSendingCode
                                  || model.resetCodeCountdown > 0
                                  || model.resetUsername.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        case 2:
            VStack(alignment: .leading, spacing: 14) {
                Text("确认后将为账号生成新密码（与 Web 端一致）。")
                    .font(.system(size: 13))
                    .foregroundColor(LoginPalette.muted(dark))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LoginPalette.panel(dark).opacity(0.6))
                    .cornerRadius(10)
                VStack(alignment: .leading, spacing: 8) {
                    Text("账号")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(LoginPalette.muted(dark))
                    Text(model.resetUsername)
                        .font(.system(size: 15, weight: .bold))
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
                Text("密码重置成功")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundColor(LoginPalette.text(dark))
                Text(model.resetSuccessDetail.isEmpty
                     ? "请使用新密码登录（详见服务端返回信息）"
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
        HStack(spacing: 16) {
            Button(action: {
                if model.resetStep == 1 || model.resetStep == 3 {
                    onClose()
                } else {
                    onBack()
                }
            }) {
                Text(model.resetStep == 3 ? "完成" : (model.resetStep == 1 ? "取消" : "上一步"))
                    .font(.system(size: 15, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .foregroundColor(LoginPalette.text(dark))
                    .background(LoginPalette.oauthBg(dark))
                    .cornerRadius(999)
                    .overlay(
                        RoundedRectangle(cornerRadius: 999)
                            .stroke(LoginPalette.oauthBorder(dark), lineWidth: 1)
                    )
            }
            .buttonStyle(PlainButtonStyle())

            if model.resetStep < 3 {
                Button(action: onNext) {
                    HStack(spacing: 8) {
                        if model.resetBusy {
                            ProgressView().scaleEffect(0.7)
                        }
                        Text(model.resetStep == 1 ? "下一步" : "确认重置")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .foregroundColor(.white)
                    .background(LoginPalette.primary(dark))
                    .cornerRadius(999)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(model.resetBusy)
                .opacity(model.resetBusy ? 0.7 : 1)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(LoginPalette.panel(dark).opacity(0.45))
        .overlay(Rectangle().fill(LoginPalette.line(dark)).frame(height: 1), alignment: .top)
    }
}
