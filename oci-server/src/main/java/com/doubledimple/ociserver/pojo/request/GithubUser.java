package com.doubledimple.ociserver.pojo.request;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * @version 1.0.0
 * @ClassName GithubUser
 * @Description TODO
 * @Author doubleDimple
 * @Date 2024-11-21 16:12
 */
@Data
@AllArgsConstructor
@NoArgsConstructor
public class GithubUser {
    private Long id;
    private String login;
    private String name;
    private String email;
}
