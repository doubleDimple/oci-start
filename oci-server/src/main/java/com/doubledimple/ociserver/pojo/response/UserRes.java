package com.doubledimple.ociserver.pojo.response;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.Date;

/**
 * @version 1.0.0
 * @ClassName UserRes
 * @Description TODO
 * @Author doubleDimple
 * @Date 2024-12-21 22:15
 */
@Data
@AllArgsConstructor
@NoArgsConstructor
public class UserRes {

    private String id;
    private String username;       // 用户名
    private String lifecycleState; // 用户状态 (ACTIVE / INACTIVE)
    private String userId;         // 用户 OCID
    private String email;
    //最后一次登录时间
    private Date lastSuccessfulLoginTime;
    //创建时间
    private Date timeCreated;

    private String domain;
}
