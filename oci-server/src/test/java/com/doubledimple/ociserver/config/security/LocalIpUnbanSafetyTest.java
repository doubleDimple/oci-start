package com.doubledimple.ociserver.config.security;

import org.junit.jupiter.api.Test;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;

/** Exercises recovery SQL against disposable in-memory H2 databases only. */
class LocalIpUnbanSafetyTest {
    @Test
    void releasesAllLocalhostBansAndCountersWhilePreservingHistoryAndOtherIps() throws Exception {
        try (Connection connection = database(true)) {
            int[] counts = LocalIpUnbanTest.releaseLoopback(connection);

            assertArrayEquals(new int[]{2, 1}, counts);
            assertEquals(0, count(connection, "SELECT COUNT(*) FROM ban_record WHERE ip_address = '127.0.0.1' AND status = 1"));
            assertEquals(0, count(connection, "SELECT COUNT(*) FROM login_failure_state WHERE ip_address = '127.0.0.1'"));
            assertEquals(4, count(connection, "SELECT COUNT(*) FROM ban_record"));
            assertEquals(1, count(connection, "SELECT COUNT(*) FROM ban_record WHERE id = 3 AND status = 1"));
            assertEquals(1, count(connection, "SELECT COUNT(*) FROM login_failure_state WHERE ip_address = '192.0.2.20' AND wrong_password_count = 2"));
            assertEquals(2, count(connection, "SELECT COUNT(*) FROM ban_record WHERE id IN (1, 2) AND status = 0"
                    + " AND unban_time IS NOT NULL AND unban_operator_name = 'local-recovery-test'"
                    + " AND reason = 'original reason' AND operator_name = 'system'"));
            assertEquals(1, count(connection, "SELECT COUNT(*) FROM ban_record WHERE id = 4"
                    + " AND unban_reason = 'earlier release' AND unban_operator_name = 'admin'"));
        }
    }

    @Test
    void failureToClearCountersRollsBackTheBanChange() throws Exception {
        try (Connection connection = database(false)) {
            assertThrows(SQLException.class, () -> LocalIpUnbanTest.releaseLoopback(connection));

            assertEquals(2, count(connection, "SELECT COUNT(*) FROM ban_record WHERE ip_address = '127.0.0.1' AND status = 1"));
            assertEquals(0, count(connection, "SELECT COUNT(*) FROM ban_record WHERE unban_operator_name = 'local-recovery-test'"));
        }
    }

    @Test
    void repeatedRecoveryDoesNotAlterPreviouslyReleasedRecords() throws Exception {
        try (Connection connection = database(true)) {
            LocalIpUnbanTest.releaseLoopback(connection);
            connection.setAutoCommit(true);

            assertArrayEquals(new int[]{0, 0}, LocalIpUnbanTest.releaseLoopback(connection));
            assertEquals(4, count(connection, "SELECT COUNT(*) FROM ban_record"));
            assertEquals(1, count(connection, "SELECT COUNT(*) FROM ban_record WHERE id = 3 AND status = 1"));
        }
    }

    private static Connection database(boolean withCounters) throws SQLException {
        Connection connection = DriverManager.getConnection("jdbc:h2:mem:unban_" + UUID.randomUUID(), "sa", "");
        try (Statement statement = connection.createStatement()) {
            statement.execute("CREATE TABLE ban_record (id BIGINT PRIMARY KEY, ip_address VARCHAR(64), status INT,"
                    + " unban_time TIMESTAMP, unban_reason VARCHAR(255), unban_operator_name VARCHAR(64),"
                    + " reason VARCHAR(255), operator_name VARCHAR(64))");
            statement.execute("INSERT INTO ban_record (id, ip_address, status, reason, operator_name) VALUES"
                    + " (1, '127.0.0.1', 1, 'original reason', 'system'),"
                    + " (2, '127.0.0.1', 1, 'original reason', 'system'),"
                    + " (3, '192.0.2.20', 1, 'original reason', 'system')");
            statement.execute("INSERT INTO ban_record (id, ip_address, status, unban_reason, unban_operator_name)"
                    + " VALUES (4, '127.0.0.1', 0, 'earlier release', 'admin')");
            if (withCounters) {
                statement.execute("CREATE TABLE login_failure_state (ip_address VARCHAR(64) PRIMARY KEY, wrong_password_count INT)");
                statement.execute("INSERT INTO login_failure_state VALUES ('127.0.0.1', 3), ('192.0.2.20', 2)");
            }
        }
        return connection;
    }

    private static int count(Connection connection, String sql) throws SQLException {
        try (Statement statement = connection.createStatement(); ResultSet result = statement.executeQuery(sql)) {
            assertTrue(result.next());
            return result.getInt(1);
        }
    }
}
