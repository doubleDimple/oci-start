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
 * 本地手动解封
 *
 */
@EnabledIfSystemProperty(named = "oci.local-unban", matches = "true")
class LocalIpUnbanTest {
    private static final String IP = "127.0.0.1";

    @Test
    void unbanLocalhost() throws Exception {
        Path root = projectRoot();
        Path databaseFile = root.resolve("data/vps_db.mv.db");
        if (!Files.isRegularFile(databaseFile)) {
            throw new IllegalStateException("本地数据库不存在，未执行解封：" + databaseFile);
        }
        String databasePath = databaseFile.toRealPath().toString();
        if (databasePath.contains(";")) {
            throw new IllegalStateException("数据库路径不能包含 H2 连接参数分隔符");
        }
        String databaseBase = databasePath.substring(0, databasePath.length() - ".mv.db".length());

        // Parse without Spring's YAML debug logging, which can print database credentials.
        Properties properties = new Properties();
        try (InputStream input = Files.newInputStream(root.resolve("oci-server/src/main/resources/application.yml"))) {
            Map<?, ?> configuration = new Yaml(new SafeConstructor(new LoaderOptions())).load(input);
            Map<?, ?> spring = (Map<?, ?>) configuration.get("spring");
            Map<?, ?> datasource = (Map<?, ?>) spring.get("datasource");
            for (String key : new String[]{"username", "password"}) {
                Object value = datasource.get(key);
                if (value != null) properties.setProperty("spring.datasource." + key, value.toString());
            }
        }
        StandardEnvironment environment = new StandardEnvironment();
        environment.getPropertySources().addLast(new PropertiesPropertySource("localApplication", properties));
        String username = environment.getRequiredProperty("spring.datasource.username");
        String password = environment.getRequiredProperty("spring.datasource.password");

        System.out.println("本地解封目标：" + databaseFile.toRealPath() + "；IP=" + IP);
        // IFEXISTS prevents accidental creation of a different, empty database. Keep normal file locking.
        try (Connection connection = DriverManager.getConnection(
                "jdbc:h2:file:" + databaseBase + ";IFEXISTS=TRUE;DB_CLOSE_ON_EXIT=FALSE", username, password)) {
            int[] counts = releaseLoopback(connection);
            System.out.println("解封已提交：IP=" + IP + "，解除封禁 " + counts[0]
                    + " 条，清除失败计数 " + counts[1] + " 条。可以重新启动应用登录。");
        } catch (SQLException e) {
            if (e.getErrorCode() == 90020) {
                throw new IllegalStateException("数据库仍被占用。请先停止 OciServerApplication，再运行此测试。", e);
            }
            throw e;
        }
    }

    /** Uses a fresh connection; failure of either change rolls back both changes. */
    static int[] releaseLoopback(Connection connection) throws SQLException {
        if (!connection.getAutoCommit()) {
            throw new IllegalArgumentException("解封必须使用独立数据库连接");
        }
        connection.setAutoCommit(false);
        try {
            int released;
            try (PreparedStatement update = connection.prepareStatement(
                    "UPDATE ban_record SET status = 0, unban_time = CURRENT_TIMESTAMP,"
                            + " unban_reason = ?, unban_operator_name = ? WHERE ip_address = ? AND status = 1")) {
                update.setString(1, "本地手动测试解封");
                update.setString(2, "local-recovery-test");
                update.setString(3, IP);
                released = update.executeUpdate();
            }
            int cleared;
            try (PreparedStatement delete = connection.prepareStatement(
                    "DELETE FROM login_failure_state WHERE ip_address = ?")) {
                delete.setString(1, IP);
                cleared = delete.executeUpdate();
            }
            try (PreparedStatement verify = connection.prepareStatement(
                    "SELECT (SELECT COUNT(*) FROM ban_record WHERE ip_address = ? AND status = 1)"
                            + " + (SELECT COUNT(*) FROM login_failure_state WHERE ip_address = ?)")) {
                verify.setString(1, IP);
                verify.setString(2, IP);
                try (ResultSet result = verify.executeQuery()) {
                    if (!result.next() || result.getInt(1) != 0) {
                        throw new SQLException("解封检查未通过，撤销本次修改");
                    }
                }
            }
            connection.commit();
            return new int[]{released, cleared};
        } catch (SQLException | RuntimeException e) {
            try {
                connection.rollback();
            } catch (SQLException rollbackFailure) {
                e.addSuppressed(rollbackFailure);
            }
            throw e;
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
