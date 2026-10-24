package com.doubledimple.ociserver.config.security;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfSystemProperty;
import org.springframework.core.env.PropertiesPropertySource;
import org.springframework.core.env.StandardEnvironment;
import org.yaml.snakeyaml.LoaderOptions;
import org.yaml.snakeyaml.Yaml;
import org.yaml.snakeyaml.constructor.SafeConstructor;

import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.Map;
import java.util.Properties;

/**
 * 本地手动恢复登录：先停止应用，再以 VM 参数 -Doci.local-unban=true 运行此类。
 * 默认跳过；不启动 Spring、不发送通知，不清理用户、租户或导出限制。
 * 使用 application.yml 和激活的 profile；相对数据库路径以项目根目录为基准。
 * 非默认文件可显式指定 -Doci.local-db-file=/absolute/path/vps_db.mv.db。
 */
@EnabledIfSystemProperty(named = "oci.local-unban", matches = "true")
class LocalIpUnbanTest {
    private static final String[] LOOPBACK_IPS = {"127.0.0.1", "::1", "0:0:0:0:0:0:0:1"};
    private static final String GLOBAL_STATE_KEY = "auth.login.global-state";

    @Test
    void unbanLocalhost() throws Exception {
        Path root = projectRoot();
        StandardEnvironment environment = localEnvironment(root);
        String explicitFile = environment.getProperty("oci.local-db-file");
        Path databaseFile;
        if (explicitFile != null && !explicitFile.trim().isEmpty()) {
            databaseFile = root.resolve(explicitFile.trim()).normalize();
        } else {
            String url = environment.getRequiredProperty("spring.datasource.url");
            if (!url.startsWith("jdbc:h2:file:")) {
                throw new IllegalStateException("仅支持现有本地 H2 文件；请显式指定 oci.local-db-file");
            }
            String base = url.substring("jdbc:h2:file:".length()).split(";", 2)[0];
            if (base.startsWith("~/")) base = System.getProperty("user.home") + base.substring(1);
            databaseFile = root.resolve(base + ".mv.db").normalize();
        }
        if (!databaseFile.getFileName().toString().endsWith(".mv.db")) {
            throw new IllegalStateException("本地数据库文件必须以 .mv.db 结尾");
        }
        if (!Files.isRegularFile(databaseFile)) {
            throw new IllegalStateException("本地数据库不存在，未执行解封：" + databaseFile);
        }
        String databasePath = databaseFile.toRealPath().toString();
        if (databasePath.contains(";")) {
            throw new IllegalStateException("数据库路径不能包含 H2 连接参数分隔符");
        }
        String databaseBase = databasePath.substring(0, databasePath.length() - ".mv.db".length());

        String username = environment.getRequiredProperty("spring.datasource.username");
        String password = environment.getRequiredProperty("spring.datasource.password");

        System.out.println("本地解封目标：" + databaseFile.toRealPath() + "；解除全站登录锁及本机回环 IP 封禁");
        // IFEXISTS prevents accidental creation of a different, empty database. Keep normal file locking.
        try (Connection connection = DriverManager.getConnection(
                "jdbc:h2:file:" + databaseBase + ";IFEXISTS=TRUE;AUTO_SERVER=FALSE;DB_CLOSE_ON_EXIT=FALSE", username, password)) {
            int[] counts = releaseLocalLogin(connection);
            System.out.println("解封已提交：重置全站登录状态 " + counts[2] + " 条，解除本机 IP 封禁 " + counts[0]
                    + " 条，清除本机失败计数 " + counts[1] + " 条。用户、租户和导出限制均保留，可以重新启动应用登录。");
        } catch (SQLException e) {
            if (e.getErrorCode() == 90020) {
                throw new IllegalStateException("数据库仍被占用。请先停止 OciServerApplication，再运行此测试。", e);
            }
            throw e;
        }
    }

    /** Uses a fresh connection; failure of either change rolls back both changes. */
    static int[] releaseLoopback(Connection connection) throws SQLException {
        return release(connection, false);
    }

    /** Reset the entire v2/v3 lock, including its recovery code, together with loopback IP failures. */
    static int[] releaseLocalLogin(Connection connection) throws SQLException {
        return release(connection, true);
    }

    private static int[] release(Connection connection, boolean resetGlobalLogin) throws SQLException {
        if (!connection.getAutoCommit()) {
            throw new IllegalArgumentException("解封必须使用独立数据库连接");
        }
        connection.setAutoCommit(false);
        try {
            int global = 0;
            if (resetGlobalLogin) {
                try (PreparedStatement update = connection.prepareStatement(
                        "UPDATE system_config SET config_value = 'v2|0|', config_enabled = FALSE,"
                                + " last_modified = CURRENT_TIMESTAMP WHERE config_key = ?")) {
                    update.setString(1, GLOBAL_STATE_KEY);
                    global = update.executeUpdate();
                }
            }
            int released;
            try (PreparedStatement update = connection.prepareStatement(
                    "UPDATE ban_record SET status = 0, unban_time = CURRENT_TIMESTAMP,"
                            + " unban_reason = ?, unban_operator_name = ? WHERE ip_address IN (?, ?, ?) AND status = 1")) {
                update.setString(1, "本地手动测试解封");
                update.setString(2, "local-recovery-test");
                bindLoopbacks(update, 3);
                released = update.executeUpdate();
            }
            int cleared;
            try (PreparedStatement delete = connection.prepareStatement(
                    "DELETE FROM login_failure_state WHERE ip_address IN (?, ?, ?)")) {
                bindLoopbacks(delete, 1);
                cleared = delete.executeUpdate();
            }
            try (PreparedStatement verify = connection.prepareStatement(
                    "SELECT (SELECT COUNT(*) FROM ban_record WHERE ip_address IN (?, ?, ?) AND status = 1)"
                            + " + (SELECT COUNT(*) FROM login_failure_state WHERE ip_address IN (?, ?, ?))")) {
                bindLoopbacks(verify, 1);
                bindLoopbacks(verify, 4);
                try (ResultSet result = verify.executeQuery()) {
                    if (!result.next() || result.getInt(1) != 0) {
                        throw new SQLException("解封检查未通过，撤销本次修改");
                    }
                }
            }
            if (resetGlobalLogin) {
                try (PreparedStatement verify = connection.prepareStatement(
                        "SELECT COUNT(*) FROM system_config WHERE config_key = ?"
                                + " AND (config_value IS NULL OR config_value <> 'v2|0|'"
                                + " OR config_enabled IS NULL OR config_enabled <> FALSE)")) {
                    verify.setString(1, GLOBAL_STATE_KEY);
                    try (ResultSet result = verify.executeQuery()) {
                        if (!result.next() || result.getInt(1) != 0) {
                            throw new SQLException("全站登录状态检查未通过，撤销本次修改");
                        }
                    }
                }
            }
            connection.commit();
            return resetGlobalLogin ? new int[]{released, cleared, global} : new int[]{released, cleared};
        } catch (SQLException | RuntimeException e) {
            try {
                connection.rollback();
            } catch (SQLException rollbackFailure) {
                e.addSuppressed(rollbackFailure);
            }
            throw e;
        }
    }

    private static void bindLoopbacks(PreparedStatement statement, int start) throws SQLException {
        for (int i = 0; i < LOOPBACK_IPS.length; i++) statement.setString(start + i, LOOPBACK_IPS[i]);
    }

    private static StandardEnvironment localEnvironment(Path root) throws Exception {
        Properties properties = new Properties();
        Path resources = root.resolve("oci-server/src/main/resources");
        readLocalProperties(resources.resolve("application.yml"), properties);
        StandardEnvironment environment = new StandardEnvironment();
        environment.getPropertySources().addLast(new PropertiesPropertySource("localApplication", properties));
        String profiles = environment.getProperty("spring.profiles.active", "");
        for (String value : profiles.split(",")) {
            String profile = value.trim();
            if (profile.isEmpty()) continue;
            if (!profile.matches("[A-Za-z0-9_-]+")) throw new IllegalStateException("本地 profile 名称无效");
            Path file = resources.resolve("application-" + profile + ".yml");
            if (Files.isRegularFile(file)) readLocalProperties(file, properties);
        }
        return environment;
    }

    /** Parse only local configuration values, without YAML debug output or application startup. */
    private static void readLocalProperties(Path file, Properties properties) throws Exception {
        try (InputStream input = Files.newInputStream(file)) {
            Map<?, ?> configuration = new Yaml(new SafeConstructor(new LoaderOptions())).load(input);
            Object springValue = configuration == null ? null : configuration.get("spring");
            if (!(springValue instanceof Map)) return;
            Map<?, ?> spring = (Map<?, ?>) springValue;
            Object datasource = spring.get("datasource");
            if (datasource instanceof Map) {
                for (String key : new String[]{"url", "username", "password"}) {
                    Object value = ((Map<?, ?>) datasource).get(key);
                    if (value != null) properties.setProperty("spring.datasource." + key, value.toString());
                }
            }
            Object profiles = spring.get("profiles");
            if (profiles instanceof Map && ((Map<?, ?>) profiles).get("active") != null) {
                properties.setProperty("spring.profiles.active", ((Map<?, ?>) profiles).get("active").toString());
            }
        }
    }

    private static Path projectRoot() {
        for (Path path = Paths.get("").toAbsolutePath().normalize(); path != null; path = path.getParent()) {
            if (Files.isRegularFile(path.resolve("pom.xml"))
                    && Files.isRegularFile(path.resolve("oci-server/pom.xml"))) {
                return path;
            }
        }
        throw new IllegalStateException("请把测试 Working directory 设置为项目根目录或 oci-server 目录");
    }
}
