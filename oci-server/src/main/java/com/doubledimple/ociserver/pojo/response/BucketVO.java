package com.doubledimple.ociserver.pojo.response;

import lombok.Builder;
import lombok.Data;

@Data
@Builder
public class BucketVO {

    private String name;
    private String namespace;
    private String timeCreated;
    private String publicAccess;
}
