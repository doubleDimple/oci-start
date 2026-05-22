package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

/**
 * @version 1.0.0
 * @ClassName GithubConfigRequest
 * @Description TODO
 * @Author doubleDimple
 * @Date 2024-11-21 12:59
 */
@Data
public class GithubConfigRequest {
    private String clientId;
    private String clientSecret;
    private String redirectUri;
    private String githubId;
    private String userName;
    private boolean enabled;
}
