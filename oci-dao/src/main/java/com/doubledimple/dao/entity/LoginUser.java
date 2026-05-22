package com.doubledimple.dao.entity;

import com.doubledimple.ocicommon.enums.LoginTypeEnum;
import lombok.Data;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.EnumType;
import javax.persistence.Enumerated;
import javax.persistence.GeneratedValue;
import javax.persistence.GenerationType;
import javax.persistence.Id;
import javax.persistence.Table;
import java.time.LocalDateTime;

/**
 * @version 1.0.0
 * @ClassName LoginUser
 * @Description TODO
 * @Author doubleDimple
 * @Date 2024-11-21 10:58
 */
@Entity
@Table(name = "login_user")
@Data
public class LoginUser {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(unique = true, nullable = false)
    private String username;

    @Column(nullable = false)
    private String password;

    private boolean isFirstUser;

    // 添加登录类型枚举
    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private LoginTypeEnum loginType = LoginTypeEnum.LOCAL;

    // 添加第三方账号ID
    private String externalId;

    @Column(name = "last_login_at")
    private LocalDateTime lastLoginAt;



}
