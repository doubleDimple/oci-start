package com.doubledimple.ociserver.pojo.request;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.Data;

@Data
public class GoogleUser {
    private String sub; // Google的唯一用户ID
    private String name;
    private String email;
    private String picture;

    @JsonProperty("email_verified")
    private boolean emailVerified;
}
