package com.doubledimple.ociserver.service.login;

/** DTO/exception fixtures for controller boundary tests; persistence behavior uses the real guard separately. */
public final class GlobalLoginGuardTestSupport {
    public static final String BLOCKED_MESSAGE = "登录凭据已连续验证失败 3 次，本站登录入口已封禁";
    private GlobalLoginGuardTestSupport() { }

    public static GlobalLoginGuard.LoginStatus status(boolean blocked) {
        try {
            java.lang.reflect.Constructor<GlobalLoginGuard.LoginStatus> constructor =
                    GlobalLoginGuard.LoginStatus.class.getDeclaredConstructor(boolean.class, String.class);
            constructor.setAccessible(true);
            return constructor.newInstance(blocked, blocked ? "2026-10-25T00:00+08:00" : null);
        } catch (ReflectiveOperationException exception) { throw new AssertionError(exception); }
    }

    public static GlobalLoginGuard.LoginGuardException blockedException() {
        try {
            java.lang.reflect.Constructor<GlobalLoginGuard.LoginGuardException> constructor =
                    GlobalLoginGuard.LoginGuardException.class.getDeclaredConstructor(String.class, boolean.class, String.class);
            constructor.setAccessible(true);
            return constructor.newInstance(BLOCKED_MESSAGE, true, "2026-10-25T00:00+08:00");
        } catch (ReflectiveOperationException exception) { throw new AssertionError(exception); }
    }
}
