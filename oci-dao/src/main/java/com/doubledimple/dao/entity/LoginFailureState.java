package com.doubledimple.dao.entity;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Id;
import javax.persistence.Table;
import java.time.LocalDateTime;

/**
 * 每个来源 IP 自上次完整登录成功或人工解封后的失败次数。
 * 不存储用户名、密码或其他登录凭据，也不按时间自动重置。
 */
@Entity
@Table(name = "login_failure_state")
public class LoginFailureState {

    @Id
    @Column(name = "ip_address", nullable = false, length = 64)
    private String ipAddress;

    @Column(name = "unknown_username_count", nullable = false)
    private int unknownUsernameCount;

    @Column(name = "wrong_password_count", nullable = false)
    private int wrongPasswordCount;

    @Column(name = "last_failure_time", nullable = false)
    private LocalDateTime lastFailureTime;

    public String getIpAddress() {
        return ipAddress;
    }

    public void setIpAddress(String ipAddress) {
        this.ipAddress = ipAddress;
    }

    public int getUnknownUsernameCount() {
        return unknownUsernameCount;
    }

    public void setUnknownUsernameCount(int unknownUsernameCount) {
        this.unknownUsernameCount = unknownUsernameCount;
    }

    public int getWrongPasswordCount() {
        return wrongPasswordCount;
    }

    public void setWrongPasswordCount(int wrongPasswordCount) {
        this.wrongPasswordCount = wrongPasswordCount;
    }

    public LocalDateTime getLastFailureTime() {
        return lastFailureTime;
    }

    public void setLastFailureTime(LocalDateTime lastFailureTime) {
        this.lastFailureTime = lastFailureTime;
    }
}
