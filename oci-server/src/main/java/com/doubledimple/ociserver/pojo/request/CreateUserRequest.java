package com.doubledimple.ociserver.pojo.request;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * @version 1.0.0
 * @ClassName CreateUserRequest
 * @Description TODO
 * @Author doubleDimple
 * @Date 2024-12-21 22:24
 */
@Data
@AllArgsConstructor
@NoArgsConstructor
public class CreateUserRequest {
    private String tenantId;    // 租户 OCID
    private String username;    // 用户名
    private String email;    // 用户密码（模拟字段，可根据需求处理）

    private String groupId;
}