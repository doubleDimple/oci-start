package com.doubledimple.ociserver.config.security;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.core.env.Environment;
import org.springframework.core.env.ConfigurableEnvironment;
import org.springframework.core.env.StandardEnvironment;
import org.springframework.test.util.ReflectionTestUtils;

import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Proxy;
import java.sql.*;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.Callable;
import java.util.concurrent.atomic.AtomicBoolean;

import static org.junit.jupiter.api.Assertions.*;

/** Runs only disposable in-memory H2 SQL; never enables or invokes the file-database runner. */
/*class LocalLoginUnbanSafetyTest {
    private static final String KEY = "auth.login.global-state";
    private static final String RECOVERY_HASH = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    private static final String V3 = "v3|3|2027-10-24T15:59:30Z|00000000-0000-0000-0000-000000000071|"
            + RECOVERY_HASH + "|1234567|bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb||0";
    private static final String LOOPBACK = "('127.0.0.1', '::1', '0:0:0:0:0:0:0:1')";

    @ParameterizedTest
    @ValueSource(strings = {V3, "v2|3|2027-10-24T15:59:30Z", "v2|2|", "2026-10-24|3"})
    void releasesTheGlobalStateAndAllLoopbackAddressesWithoutChangingAccountsHistoryOrOtherIps(String state) throws Exception {
        try (Connection connection = database(state)) {
            List<List<String>> accounts = rows(connection, "SELECT * FROM login_user ORDER BY id");
            List<List<String>> otherSettings = rows(connection, "SELECT * FROM system_config WHERE config_key <> '" + KEY + "' ORDER BY id");
            List<List<String>> historyAndOtherIps = rows(connection, "SELECT * FROM ban_record WHERE id >= 4 ORDER BY id");
            List<List<String>> remoteCounters = rows(connection, "SELECT * FROM login_failure_state WHERE ip_address NOT IN " + LOOPBACK + " ORDER BY ip_address");

            assertArrayEquals(new int[]{3, 3, 1}, LocalIpUnbanTest.releaseLocalLogin(connection));

            assertEquals("v2|0|", scalar(connection, "SELECT config_value FROM system_config WHERE config_key = '" + KEY + "'"));
            assertEquals(1, count(connection, "SELECT COUNT(*) FROM system_config WHERE config_key = '" + KEY
                    + "' AND config_enabled = FALSE AND last_modified > TIMESTAMP '2000-01-01 00:00:00'"));
            assertEquals(0, count(connection, "SELECT COUNT(*) FROM system_config WHERE config_value LIKE '%" + RECOVERY_HASH + "%'"));
            assertEquals(0, count(connection, "SELECT COUNT(*) FROM ban_record WHERE ip_address IN " + LOOPBACK + " AND status = 1"));
            assertEquals(0, count(connection, "SELECT COUNT(*) FROM login_failure_state WHERE ip_address IN " + LOOPBACK));
            assertEquals(3, count(connection, "SELECT COUNT(*) FROM ban_record WHERE id IN (1, 2, 3) AND status = 0"
                    + " AND unban_time IS NOT NULL AND unban_operator_name = 'local-recovery-test'"
                    + " AND reason = 'original reason' AND operator_name = 'system'"));
            assertEquals(7, count(connection, "SELECT COUNT(*) FROM ban_record"));
            assertEquals(accounts, rows(connection, "SELECT * FROM login_user ORDER BY id"));
            assertEquals(otherSettings, rows(connection, "SELECT * FROM system_config WHERE config_key <> '" + KEY + "' ORDER BY id"));
            assertEquals(historyAndOtherIps, rows(connection, "SELECT * FROM ban_record WHERE id >= 4 ORDER BY id"));
            assertEquals(remoteCounters, rows(connection, "SELECT * FROM login_failure_state WHERE ip_address NOT IN " + LOOPBACK + " ORDER BY ip_address"));
        }
    }

    @Test
    void aVerificationSqlFailureAfterTheGlobalUpdateRollsBackEveryChange() throws Exception {
        try (Connection connection = database(V3)) {
            List<List<String>> bansBefore = rows(connection, "SELECT * FROM ban_record ORDER BY id");
            List<List<String>> failuresBefore = rows(connection, "SELECT * FROM login_failure_state ORDER BY ip_address");
            List<List<String>> settingsBefore = rows(connection, "SELECT * FROM system_config ORDER BY id");
            AtomicBoolean globalUpdated = new AtomicBoolean();
            AtomicBoolean verificationFailedAfterAllChanges = new AtomicBoolean();
            Connection failing = (Connection) Proxy.newProxyInstance(getClass().getClassLoader(), new Class<?>[]{Connection.class}, (proxy, method, arguments) -> {
                if ("prepareStatement".equals(method.getName()) && arguments[0] instanceof String) {
                    String sql = ((String) arguments[0]).trim().toUpperCase(Locale.ROOT);
                    if (globalUpdated.get() && sql.startsWith("SELECT")) {
                        verificationFailedAfterAllChanges.set("v2|0|".equals(scalar(connection,
                                "SELECT config_value FROM system_config WHERE config_key = '" + KEY + "'"))
                                && count(connection, "SELECT COUNT(*) FROM ban_record WHERE ip_address IN " + LOOPBACK + " AND status = 1") == 0
                                && count(connection, "SELECT COUNT(*) FROM login_failure_state WHERE ip_address IN " + LOOPBACK) == 0);
                        throw new SQLException("simulated final verification failure");
                    }
                    PreparedStatement statement = (PreparedStatement) invoke(connection, method, arguments);
                    if (sql.startsWith("UPDATE SYSTEM_CONFIG")) {
                        return Proxy.newProxyInstance(getClass().getClassLoader(), new Class<?>[]{PreparedStatement.class}, (statementProxy, statementMethod, statementArguments) -> {
                            Object result = invoke(statement, statementMethod, statementArguments);
                            if ("executeUpdate".equals(statementMethod.getName())) globalUpdated.set(true);
                            return result;
                        });
                    }
                    return statement;
                }
                return invoke(connection, method, arguments);
            });

            assertThrows(SQLException.class, () -> LocalIpUnbanTest.releaseLocalLogin(failing));

            assertTrue(globalUpdated.get(), "The fault must occur after the global lock was changed");
            assertTrue(verificationFailedAfterAllChanges.get(), "All three mutations must have executed before the injected SQL failure");
            assertEquals(bansBefore, rows(connection, "SELECT * FROM ban_record ORDER BY id"));
            assertEquals(failuresBefore, rows(connection, "SELECT * FROM login_failure_state ORDER BY ip_address"));
            assertEquals(settingsBefore, rows(connection, "SELECT * FROM system_config ORDER BY id"));
        }
    }

    @Test
    void repeatedRecoveryPreservesAlreadyReleasedAuditRecordsAndNeverRecreatesASecret() throws Exception {
        try (Connection connection = database(V3)) {
            LocalIpUnbanTest.releaseLocalLogin(connection);
            List<List<String>> releasedHistory = rows(connection, "SELECT * FROM ban_record ORDER BY id");
            connection.setAutoCommit(true);

            assertArrayEquals(new int[]{0, 0, 1}, LocalIpUnbanTest.releaseLocalLogin(connection));

            assertEquals(releasedHistory, rows(connection, "SELECT * FROM ban_record ORDER BY id"));
            assertEquals("v2|0|", scalar(connection, "SELECT config_value FROM system_config WHERE config_key = '" + KEY + "'"));
            assertEquals(2, count(connection, "SELECT COUNT(*) FROM login_failure_state"));
        }
    }

    @Test
    void anAbsentGlobalRowStillAllowsLoopbackRecoveryWithoutCreatingOrChangingConfiguration() throws Exception {
        try (Connection connection = database(null)) {
            List<List<String>> settingsBefore = rows(connection, "SELECT * FROM system_config ORDER BY id");

            assertArrayEquals(new int[]{3, 3, 0}, LocalIpUnbanTest.releaseLocalLogin(connection));

            assertEquals(settingsBefore, rows(connection, "SELECT * FROM system_config ORDER BY id"));
            assertEquals(0, count(connection, "SELECT COUNT(*) FROM ban_record WHERE ip_address IN " + LOOPBACK + " AND status = 1"));
        }
    }

    @Test
    void theLegacyIpOnlyHelperKeepsTheGlobalLockAndRecoveryHashUntouched() throws Exception {
        try (Connection connection = database(V3)) {
            List<List<String>> settingsBefore = rows(connection, "SELECT * FROM system_config ORDER BY id");

            assertArrayEquals(new int[]{3, 3}, LocalIpUnbanTest.releaseLoopback(connection));

            assertEquals(settingsBefore, rows(connection, "SELECT * FROM system_config ORDER BY id"));
            assertEquals(V3, scalar(connection, "SELECT config_value FROM system_config WHERE config_key = '" + KEY + "'"));
        }
    }

    @Test
    void anExistingTransactionIsRejectedBeforeAnyRecoveryMutation() throws Exception {
        try (Connection connection = database(V3)) {
            connection.setAutoCommit(false);

            assertThrows(IllegalArgumentException.class, () -> LocalIpUnbanTest.releaseLocalLogin(connection));

            assertEquals(3, count(connection, "SELECT COUNT(*) FROM ban_record WHERE ip_address IN " + LOOPBACK + " AND status = 1"));
            assertEquals(5, count(connection, "SELECT COUNT(*) FROM login_failure_state"));
            assertEquals(V3, scalar(connection, "SELECT config_value FROM system_config WHERE config_key = '" + KEY + "'"));
        }
    }

    @Test
    void theActiveProfileOverridesBaseDatasourceSettingsWithoutOpeningAnyDatabase(@TempDir Path root) throws Exception {
        writeLocalConfiguration(root);
        withDatasourceProperties(null, () -> {
            Environment environment = ReflectionTestUtils.invokeMethod(LocalIpUnbanTest.class, "localEnvironment", root);
            assertNotNull(environment);
            // Assertions inspect fixture YAML, never a developer's exported datasource credentials.
            ((ConfigurableEnvironment) environment).getPropertySources().remove(StandardEnvironment.SYSTEM_ENVIRONMENT_PROPERTY_SOURCE_NAME);
            assertEquals("jdbc:h2:file:./data/profile-fixture", environment.getProperty("spring.datasource.url"));
            assertEquals("profile-fixture-user", environment.getProperty("spring.datasource.username"));
            assertEquals("profile-fixture-password", environment.getProperty("spring.datasource.password"));
            return null;
        });
    }

    @Test
    void explicitSystemDatasourceSettingsTakePrecedenceOverBothYamlFiles(@TempDir Path root) throws Exception {
        writeLocalConfiguration(root);
        withDatasourceProperties("system-fixture", () -> {
            Environment environment = ReflectionTestUtils.invokeMethod(LocalIpUnbanTest.class, "localEnvironment", root);
            assertNotNull(environment);
            assertEquals("jdbc:h2:file:./data/system-fixture", environment.getProperty("spring.datasource.url"));
            assertEquals("system-fixture-user", environment.getProperty("spring.datasource.username"));
            assertEquals("system-fixture-password", environment.getProperty("spring.datasource.password"));
            return null;
        });
    }

    private static void writeLocalConfiguration(Path root) throws Exception {
        Path resources = Files.createDirectories(root.resolve("oci-server/src/main/resources"));
        Files.writeString(resources.resolve("application.yml"), "spring:\n  profiles:\n    active: fixture\n  datasource:\n"
                + "    url: jdbc:h2:file:./data/base-fixture\n    username: base-fixture-user\n    password: base-fixture-password\n");
        Files.writeString(resources.resolve("application-fixture.yml"), "spring:\n  datasource:\n"
                + "    url: jdbc:h2:file:./data/profile-fixture\n    username: profile-fixture-user\n    password: profile-fixture-password\n");
    }

    private static <T> T withDatasourceProperties(String prefix, Callable<T> check) throws Exception {
        Map<String, String> previous = new LinkedHashMap<>();
        for (String key : new String[]{"spring.profiles.active", "spring.datasource.url", "spring.datasource.username", "spring.datasource.password"}) {
            previous.put(key, System.getProperty(key));
            System.clearProperty(key);
        }
        try {
            System.setProperty("spring.profiles.active", "fixture");
            if (prefix != null) {
                System.setProperty("spring.datasource.url", "jdbc:h2:file:./data/" + prefix);
                System.setProperty("spring.datasource.username", prefix + "-user");
                System.setProperty("spring.datasource.password", prefix + "-password");
            }
            return check.call();
        } finally {
            previous.forEach((key, value) -> { if (value == null) System.clearProperty(key); else System.setProperty(key, value); });
        }
    }

    private static Object invoke(Object target, java.lang.reflect.Method method, Object[] arguments) throws Throwable {
        try { return method.invoke(target, arguments); }
        catch (InvocationTargetException error) { throw error.getCause(); }
    }

    private static Connection database(String globalState) throws SQLException {
        Connection connection = DriverManager.getConnection("jdbc:h2:mem:local_login_unban_" + UUID.randomUUID(), "sa", "");
        try (Statement sql = connection.createStatement()) {
            sql.execute("CREATE TABLE ban_record (id BIGINT PRIMARY KEY, ip_address VARCHAR(64), status INT,"
                    + " unban_time TIMESTAMP, unban_reason VARCHAR(255), unban_operator_name VARCHAR(64),"
                    + " reason VARCHAR(255), operator_name VARCHAR(64))");
            sql.execute("INSERT INTO ban_record (id, ip_address, status, reason, operator_name) VALUES"
                    + " (1, '127.0.0.1', 1, 'original reason', 'system'),"
                    + " (2, '::1', 1, 'original reason', 'system'),"
                    + " (3, '0:0:0:0:0:0:0:1', 1, 'original reason', 'system'),"
                    + " (4, '192.0.2.20', 1, 'remote ban', 'admin'),"
                    + " (7, '127.0.0.10', 1, 'different address', 'admin')");
            sql.execute("INSERT INTO ban_record (id, ip_address, status, unban_time, unban_reason, unban_operator_name) VALUES"
                    + " (5, '127.0.0.1', 0, TIMESTAMP '2020-01-01 00:00:00', 'prior IPv4 release', 'old-admin'),"
                    + " (6, '::1', 0, TIMESTAMP '2020-01-02 00:00:00', 'prior IPv6 release', 'old-admin')");
            sql.execute("CREATE TABLE login_failure_state (ip_address VARCHAR(64) PRIMARY KEY, wrong_password_count INT, unknown_username_count INT)");
            sql.execute("INSERT INTO login_failure_state VALUES ('127.0.0.1', 3, 1), ('::1', 3, 2),"
                    + " ('0:0:0:0:0:0:0:1', 2, 1), ('192.0.2.20', 2, 1), ('127.0.0.10', 1, 0)");
            sql.execute("CREATE TABLE system_config (id BIGINT PRIMARY KEY, config_key VARCHAR(255) UNIQUE, config_value VARCHAR(1000), config_enabled BOOLEAN, last_modified TIMESTAMP)");
            sql.execute("INSERT INTO system_config VALUES"
                    + " (2, 'auth.login.global-state.backup', 'untouched backup', TRUE, TIMESTAMP '2000-01-01 00:00:00'),"
                    + " (3, 'auth.login.unknown-user-state', 'untouched legacy key', TRUE, TIMESTAMP '2000-01-01 00:00:00'),"
                    + " (4, 'telegram.enabled', 'untouched notification setting', TRUE, TIMESTAMP '2000-01-01 00:00:00')");
            sql.execute("CREATE TABLE login_user (id BIGINT PRIMARY KEY, username VARCHAR(255), password VARCHAR(255), export_verification_date DATE, export_verification_wrong_count INT)");
            sql.execute("INSERT INTO login_user VALUES (1, 'fixture-owner', 'fixture-password-hash', DATE '2026-10-24', 2)");
        }
        if (globalState != null) {
            try (PreparedStatement insert = connection.prepareStatement("INSERT INTO system_config VALUES (1, ?, ?, ?, TIMESTAMP '2000-01-01 00:00:00')")) {
                insert.setString(1, KEY); insert.setString(2, globalState); insert.setBoolean(3, !"v2|2|".equals(globalState));
                insert.executeUpdate();
            }
        }
        return connection;
    }

    private static List<List<String>> rows(Connection connection, String query) throws SQLException {
        List<List<String>> rows = new ArrayList<>();
        try (Statement sql = connection.createStatement(); ResultSet result = sql.executeQuery(query)) {
            while (result.next()) {
                List<String> row = new ArrayList<>();
                for (int index = 1; index <= result.getMetaData().getColumnCount(); index++) row.add(result.getString(index));
                rows.add(row);
            }
        }
        return rows;
    }

    private static String scalar(Connection connection, String query) throws SQLException {
        try (Statement sql = connection.createStatement(); ResultSet result = sql.executeQuery(query)) {
            assertTrue(result.next());
            return result.getString(1);
        }
    }

    private static int count(Connection connection, String query) throws SQLException { return Integer.parseInt(scalar(connection, query)); }
}*/
