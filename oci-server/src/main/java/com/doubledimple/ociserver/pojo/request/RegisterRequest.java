package com.doubledimple.ociserver.pojo.request;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.ToString;

/**
 * @version 1.0.0
 * @ClassName RegisterRequest
 * @Description TODO
 * @Author doubleDimple
 * @Date 2024-11-21 11:10
 */
@Data
@AllArgsConstructor
@NoArgsConstructor
@ToString
public class RegisterRequest {
    private String username;
    private String password;
}
