package com.doubledimple.ocicommon.enums.oci;

import java.util.Arrays;
import java.util.Collections;
import java.util.List;

public enum OciSocialType {
    GOOGLE("Google"),
    MICROSOFT("Microsoft"),
    FACEBOOK("Facebook"),
    LINKEDIN("LinkedIn"),
    TWITTER("Twitter"),
    APPLE("Apple"),
    OPENID_CONNECT("OpenID Connect");

    private final String serviceProviderName;

    OciSocialType(String serviceProviderName) {
        this.serviceProviderName = serviceProviderName;
    }

    public String getServiceProviderName() {
        return serviceProviderName;
    }

    public static List<String> availableLoginTypes(){
        return Collections.singletonList(GOOGLE.serviceProviderName);
    }

    //根据名称查询
    public static OciSocialType getByName(String name) {
        return Arrays.stream(values())
                .filter(type -> type.serviceProviderName.equals(name))
                .findFirst()
                .orElse(null);
    }
}
